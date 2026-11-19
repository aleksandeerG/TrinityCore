using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Text.RegularExpressions;
using System.Threading;

internal static class RealmConnection
{
    private const string Portal = "trinity.actual.battle.net";
    private const int LoginWebPort = 8081;
    private const int TimeoutMilliseconds = 10000;
    private const string ClientConfig = "ForeverLocal.wtf";

    public static void VerifyLocalTls()
    {
        IPAddress[] addresses;
        try
        {
            addresses = Dns.GetHostAddresses(Portal);
        }
        catch (SocketException)
        {
            throw new RealmConnectionException("The local portal could not be resolved. See Certificates.ps1 -HostsOnly.");
        }

        if (addresses.Length != 1 || !addresses[0].Equals(IPAddress.Loopback))
            throw new RealmConnectionException("The local portal must resolve to 127.0.0.1. See Certificates.ps1 -HostsOnly.");

        try
        {
            using (var tcp = new TcpClient(AddressFamily.InterNetwork))
            {
                IAsyncResult connect = tcp.BeginConnect(IPAddress.Loopback, LoginWebPort, null, null);
                using (WaitHandle completion = connect.AsyncWaitHandle)
                {
                    if (!completion.WaitOne(TimeoutMilliseconds))
                        throw new RealmConnectionException("Connection to the local login server timed out.");
                    tcp.EndConnect(connect);
                }

                using (var tls = new SslStream(tcp.GetStream()))
                {
                    tls.ReadTimeout = TimeoutMilliseconds;
                    tls.WriteTimeout = TimeoutMilliseconds;
                    // The standalone .NET Framework launcher rejects SslProtocols.None in its legacy compatibility mode.
                    tls.AuthenticateAsClient(Portal, null, SslProtocols.Tls12, false);
                }
            }
        }
        catch (AuthenticationException)
        {
            throw new RealmConnectionException("Windows rejected the local login certificate. Check the realm's certificate and Windows trust setup.");
        }
        catch (IOException)
        {
            throw new RealmConnectionException("TLS negotiation with the local login server did not finish. Check the login server logs.");
        }
        catch (SocketException)
        {
            throw new RealmConnectionException("Could not reach the local login server on port 8081.");
        }
        catch (Win32Exception)
        {
            throw new RealmConnectionException("Windows could not validate the local login certificate. Check the realm's certificate and Windows trust setup.");
        }
    }

    public static bool IsClientExecutable(string executable)
    {
        if (!File.Exists(executable) || !Path.IsPathRooted(executable))
            return false;
        string name = Path.GetFileName(executable);
        return name.Equals("Wow.exe", StringComparison.OrdinalIgnoreCase) ||
            name.Equals("WowB.exe", StringComparison.OrdinalIgnoreCase);
    }

    public static Process StartClient(string executable)
    {
        if (!IsClientExecutable(executable))
            throw new RealmConnectionException("The selected client could not be found. Choose its executable again.");
        if (IsRunning("Wow") || IsRunning("WowB"))
            throw new RealmConnectionException("Close the running WoW client before opening the local realm.");

        string folder = Path.GetDirectoryName(executable);
        try
        {
            PrepareProfile(folder, Path.GetFileName(executable));
        }
        catch (IOException)
        {
            throw new RealmConnectionException("Could not prepare the local realm profile in the selected client's WTF folder.");
        }
        catch (UnauthorizedAccessException)
        {
            throw new RealmConnectionException("Windows denied access to the selected client's WTF folder.");
        }

        try
        {
            var settings = new ProcessStartInfo(executable, "-config " + ClientConfig)
            {
                WorkingDirectory = folder,
                UseShellExecute = false,
            };
            Process process = Process.Start(settings);
            if (process == null)
                throw new RealmConnectionException("Windows did not start the selected client.");
            return process;
        }
        catch (Win32Exception ex)
        {
            throw new RealmConnectionException("Windows could not start the selected client (error " + ex.NativeErrorCode + ").");
        }
    }

    private static bool IsRunning(string name)
    {
        Process[] processes = Process.GetProcessesByName(name);
        foreach (Process process in processes)
            process.Dispose();
        return processes.Length > 0;
    }

    internal static void PrepareProfile(string gameFolder, string executableName)
    {
        string wtfFolder = Path.Combine(gameFolder, "WTF");
        Directory.CreateDirectory(wtfFolder);
        string profile = Path.Combine(wtfFolder, ClientConfig);
        string source = File.Exists(profile) ? profile : Path.Combine(wtfFolder, "Config.wtf");
        string[] original = File.Exists(source) ? File.ReadAllLines(source) : new string[0];
        var updated = original.Where(line => !Regex.IsMatch(line, @"^\s*SET\s+portal\s+", RegexOptions.IgnoreCase)).ToList();
        if (!updated.Any(line => Regex.IsMatch(line, @"^\s*SET\s+textLocale\s+", RegexOptions.IgnoreCase)))
            updated.Add("SET textLocale \"" + InstalledTextLocale(gameFolder, executableName) + "\"");
        updated.Add("SET portal \"" + Portal + "\"");
        if (source == profile && original.SequenceEqual(updated))
            return;

        string temporary = profile + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllLines(temporary, updated);
            if (File.Exists(profile))
                File.Replace(temporary, profile, null);
            else
                File.Move(temporary, profile);
        }
        finally
        {
            File.Delete(temporary);
        }
    }

    private static string InstalledTextLocale(string gameFolder, string executableName)
    {
        string manifest = Path.Combine(Path.GetDirectoryName(gameFolder), ".build.info");
        if (!File.Exists(manifest))
            return "enUS";

        string product = executableName.Equals("WowB.exe", StringComparison.OrdinalIgnoreCase) ? "wow_classic_beta" : "wowf";
        using (var reader = File.ReadLines(manifest).GetEnumerator())
        {
            if (!reader.MoveNext())
                return "enUS";
            string[] header = reader.Current.Split('|').Select(column => column.Split('!')[0]).ToArray();
            int productIndex = Array.IndexOf(header, "Product");
            int tagsIndex = Array.IndexOf(header, "Tags");
            if (productIndex == -1 || tagsIndex == -1)
                return "enUS";

            while (reader.MoveNext())
            {
                string[] fields = reader.Current.Split('|');
                if (fields.Length <= Math.Max(productIndex, tagsIndex) || fields[productIndex].Trim() != product)
                    continue;
                MatchCollection matches = Regex.Matches(fields[tagsIndex], @"\b([a-z]{2}[A-Z]{2}) text\?");
                var locales = matches.Cast<Match>().Select(match => match.Groups[1].Value).ToArray();
                return locales.Length == 0 || locales.Contains("enUS") ? "enUS" : locales[0];
            }
        }
        return "enUS";
    }
}

internal sealed class RealmConnectionException : Exception
{
    public RealmConnectionException(string message) : base(message) { }
}
