using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32.SafeHandles;

internal static class ClientLoginKey
{
    // The public Ed25519 key corresponding to EnterEncryptedModePrivateKey in AuthenticationPackets.cpp.
    private const string PublicKey = "02596F0D0C061A8B30745988FD72C59E29EC367FB0F341F28E0F08D037BAFC69";
    private const int EntryCount = 12;
    private const int EntrySize = 40;
    private const int KeyOffset = 4;
    private const int KeySize = 32;
    private const int TableSize = EntryCount * EntrySize;
    private const int ScanChunkSize = 8 * 1024 * 1024;
    private const int ScanInterval = 500;
    private const int RecheckInterval = 1000;
    private const uint ProcessAccess = 0x0400 | 0x0010 | 0x0020 | 0x0008;
    private const uint MemCommit = 0x1000;
    private const uint MemPrivate = 0x20000;
    private const uint PageReadWrite = 0x04;
    private static readonly IntPtr RegionInfoSize = (IntPtr)Marshal.SizeOf(typeof(MemoryRegion));
    private static readonly Regex RegionSetting = new Regex(@"^\s*Network\.EnterEncryptedModeRegionGroup\s*=\s*(.*?)\s*$");

    public static int ReadRegionGroup(string root)
    {
        string server = Path.Combine(root, "server");
        string config = Path.Combine(server, "worldserver.conf");
        string overrides = Path.Combine(server, "worldserver.conf.d");
        string value;
        try
        {
            value = ReadRegionSetting(config, null);
            if (Directory.Exists(overrides))
            {
                var files = Directory.EnumerateFiles(overrides, "*.conf", SearchOption.AllDirectories)
                    .Where(file => Path.GetExtension(file) == ".conf")
                    .OrderBy(file => file, StringComparer.Ordinal);
                foreach (string file in files)
                    value = ReadRegionSetting(file, value);
            }
        }
        catch (IOException)
        {
            throw new RealmConnectionException("Could not read the local region group from the worldserver configuration.");
        }
        catch (UnauthorizedAccessException)
        {
            throw new RealmConnectionException("Windows denied access to the local worldserver configuration.");
        }

        // TrinityCore applies this environment setting after the configuration files.
        value = Environment.GetEnvironmentVariable("TC_NETWORK_ENTER_ENCRYPTED_MODE_REGION_GROUP") ?? value;
        int group;
        if (!int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out group) ||
            group < 2 || group > EntryCount || group == 9)
            throw new RealmConnectionException("Set Network.EnterEncryptedModeRegionGroup to a supported local region (2–8 or 10–12).");
        return group;
    }

    private static string ReadRegionSetting(string path, string value)
    {
        foreach (string line in File.ReadLines(path))
        {
            Match match = RegionSetting.Match(line);
            if (match.Success)
                return match.Groups[1].Value;
        }
        return value;
    }

    public static void Monitor(Process process, int group, CancellationToken cancellation, IProgress<string> progress)
    {
        cancellation.ThrowIfCancellationRequested();
        if (process.HasExited)
            return;

        // Hold the original process handle while opening a second handle with explicit memory permissions.
        // Windows retains the process ID while there is an open handle to the process.
        int processId = process.Id;
        using (SafeProcessHandle memory = OpenProcess(ProcessAccess, false, processId))
        {
            if (memory.IsInvalid)
            {
                int error = Marshal.GetLastWin32Error();
                if (process.HasExited)
                    return;
                throw new RealmConnectionException("Windows could not open the running game (error " + error + "). Run the game and launcher as the same Windows user.");
            }

            byte[] key = ParsePublicKey(PublicKey);
            byte[] table = new byte[TableSize];
            byte[] chunk = new byte[ScanChunkSize];
            int offset = (group - 1) * EntrySize + KeyOffset;
            long address = 0;
            string previousStatus = null;
            while (!process.HasExited)
            {
                cancellation.ThrowIfCancellationRequested();
                if (address != 0 && !ReadTable(memory, address, table))
                    address = 0;

                bool multiple = false;
                if (address == 0)
                    address = FindTable(memory, chunk, cancellation, out multiple);

                int delay = ScanInterval;
                string status = "Sign in with the local account. Waiting for the game to prepare its login keys.";
                if (multiple)
                    status = "Waiting for the game to finish preparing its login keys. Several tables are present.";
                else if (address != 0)
                {
                    cancellation.ThrowIfCancellationRequested();
                    if (ApplyKey(memory, address, offset, key, table))
                    {
                        delay = RecheckInterval;
                        status = "Local realm key verified. If your first login failed, retry with the game open.";
                    }
                    else
                    {
                        address = 0;
                        status = "Could not verify the local realm key in the game. Retrying.";
                    }
                }

                if (status != previousStatus)
                {
                    progress.Report(status);
                    previousStatus = status;
                }
                if (cancellation.WaitHandle.WaitOne(delay))
                    cancellation.ThrowIfCancellationRequested();
            }
        }
    }

    internal static byte[] ParsePublicKey(string hex)
    {
        if (hex == null || hex.Length != KeySize * 2)
            throw new FormatException("The world server's public key must contain 64 hexadecimal characters.");
        byte[] key = new byte[KeySize];
        for (int index = 0; index < key.Length; index++)
        {
            string digitPair = hex.Substring(index * 2, 2);
            key[index] = byte.Parse(digitPair, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture);
        }
        return key;
    }

    private static long FindTable(SafeProcessHandle memory, byte[] buffer, CancellationToken cancellation, out bool multiple)
    {
        long found = 0;
        multiple = false;
        long position = 0;
        MemoryRegion region;
        while (VirtualQueryEx(memory, (IntPtr)position, out region, RegionInfoSize) != IntPtr.Zero)
        {
            cancellation.ThrowIfCancellationRequested();
            long start = region.BaseAddress.ToInt64();
            long length = region.RegionSize.ToInt64();
            if (length <= 0 || start + length <= position)
                break;

            if (IsWritablePrivateRegion(region))
            {
                for (long offset = 0; offset + TableSize <= length; )
                {
                    cancellation.ThrowIfCancellationRequested();
                    int size = (int)Math.Min(buffer.Length, length - offset);
                    IntPtr bytesRead;
                    ReadProcessMemory(memory, (IntPtr)(start + offset), buffer, (IntPtr)size, out bytesRead);
                    int count = bytesRead.ToInt32();
                    for (int index = 0; index + TableSize <= count; index += sizeof(uint))
                    {
                        if (buffer[index] != 1 || buffer[index + 1] != 0 || buffer[index + EntrySize] != 2 || !IsTable(buffer, index))
                            continue;
                        if (found != 0)
                        {
                            multiple = true;
                            return 0;
                        }
                        found = start + offset + index;
                    }

                    if (offset + size == length)
                        break;
                    // Include every four-byte-aligned candidate that straddles the end of this chunk.
                    offset += size - TableSize + sizeof(uint);
                }
            }

            position = start + length;
        }
        return found;
    }

    private static bool IsWritablePrivateRegion(MemoryRegion region)
    {
        return region.State == MemCommit && region.Type == MemPrivate && region.Protect == PageReadWrite;
    }

    internal static bool IsTable(byte[] buffer, int offset)
    {
        if (offset < 0 || offset > buffer.Length - TableSize)
            return false;

        for (int entry = 0; entry < EntryCount; entry++)
        {
            int start = offset + entry * EntrySize;
            int flag = entry == 8 ? 0 : 1;
            if (buffer[start] != entry + 1 || buffer[start + 1] != 0 || buffer[start + 2] != 0 || buffer[start + 3] != 0 ||
                buffer[start + 36] != flag || (buffer[start + 37] != 0 && buffer[start + 37] != 0x7f) ||
                buffer[start + 38] != 0 || buffer[start + 39] != 0)
                return false;

            bool nonzero = false;
            for (int index = KeyOffset; index < KeyOffset + KeySize; index++)
                nonzero |= buffer[start + index] != 0;
            if (!nonzero)
                return false;
        }
        return true;
    }

    private static bool ReadTable(SafeProcessHandle memory, long address, byte[] table)
    {
        IntPtr bytesRead;
        return ReadProcessMemory(memory, (IntPtr)address, table, (IntPtr)TableSize, out bytesRead) &&
            bytesRead.ToInt32() == TableSize && IsTable(table, 0);
    }

    private static bool ApplyKey(SafeProcessHandle memory, long address, int offset, byte[] key, byte[] table)
    {
        if (!ReadTable(memory, address, table))
            return false;
        if (HasKey(table, offset, key))
            return true;

        MemoryRegion region;
        if (VirtualQueryEx(memory, (IntPtr)address, out region, RegionInfoSize) == IntPtr.Zero ||
            !IsWritablePrivateRegion(region) || address + TableSize > region.BaseAddress.ToInt64() + region.RegionSize.ToInt64())
            return false;

        IntPtr bytesWritten;
        return WriteProcessMemory(memory, (IntPtr)(address + offset), key, (IntPtr)KeySize, out bytesWritten) &&
            bytesWritten.ToInt32() == KeySize && ReadTable(memory, address, table) && HasKey(table, offset, key);
    }

    private static bool HasKey(byte[] table, int offset, byte[] key)
    {
        for (int index = 0; index < key.Length; index++)
            if (table[offset + index] != key[index])
                return false;
        return true;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryRegion
    {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint AllocationProtect;
        public IntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern SafeProcessHandle OpenProcess(uint access, bool inherit, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualQueryEx(SafeProcessHandle process, IntPtr address, out MemoryRegion region, IntPtr size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(SafeProcessHandle process, IntPtr address, [Out] byte[] buffer, IntPtr size, out IntPtr bytesRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteProcessMemory(SafeProcessHandle process, IntPtr address, byte[] buffer, IntPtr size, out IntPtr bytesWritten);
}
