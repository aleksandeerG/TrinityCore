using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class ForeverLocalLauncher
{
    [STAThread]
    private static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        string python = args.Length == 0 ? FindPythonOnPath() : args.Length == 1 ? args[0] : null;
        if (string.IsNullOrEmpty(python) || !Path.IsPathRooted(python) || !File.Exists(python))
        {
            MessageBox.Show("Could not find Python. Open the Desktop shortcut or add Python to your Windows PATH.", "WoW Forever Local");
            return;
        }

        bool firstInstance;
        using (var instance = new Mutex(true, @"Local\WoWForeverSourceLauncher", out firstInstance))
        {
            if (!firstInstance)
            {
                MessageBox.Show("WoW Forever Local is already open.", "WoW Forever Local");
                return;
            }

            try
            {
                string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
                using (var window = new LauncherWindow(root, python))
                    Application.Run(window);
            }
            finally
            {
                instance.ReleaseMutex();
            }
        }
    }

    private static string FindPythonOnPath()
    {
        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        string windowsApps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps");
        foreach (string entry in path.Split(Path.PathSeparator))
        {
            string directory = entry.Trim().Trim('"');
            if (directory.Length < 3 || directory[1] != ':' || directory[2] != '\\' ||
                directory.IndexOfAny(Path.GetInvalidPathChars()) >= 0)
                continue;

            if (directory.TrimEnd('\\').Equals(windowsApps, StringComparison.OrdinalIgnoreCase))
                continue;

            string python = Path.Combine(directory, "python.exe");
            if (File.Exists(python))
                return python;
        }
        return null;
    }
}

internal sealed class LauncherWindow : Form
{
    private readonly string root;
    private readonly string python;
    private readonly Label status;
    private readonly FlowLayoutPanel controls;
    private readonly FlowLayoutPanel playControls;
    private readonly Button play;
    private readonly Label clientStatus;
    private readonly Label connectionStatus;
    private readonly Label clientLoginStatus;
    private readonly TextBox account;
    private readonly TextBox password;
    private readonly CheckBox showPassword;
    private readonly Button copyAccount;
    private readonly Button copyPassword;
    private readonly Label loginStatus;
    private string clientPath;
    private CancellationTokenSource clientCancellation;
    private Task clientMonitor;
    private bool closing;
    private bool busy;

    public LauncherWindow(string root, string python)
    {
        this.root = root;
        this.python = python;
        Text = "WoW Forever Local";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(680, 470);
        MinimumSize = new Size(620, 510);
        AutoScaleMode = AutoScaleMode.Font;
        Font = new Font("Segoe UI", 10);
        Padding = new Padding(18);

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, AutoScroll = true };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Controls.Add(layout);

        var server = new GroupBox { Text = "Local server", Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(12) };
        var serverLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, AutoSize = true };
        status = new Label { Text = "Checking server status...", AutoSize = true, Margin = new Padding(3, 3, 3, 8) };
        controls = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        AddServerButton("Start", "start", "Starting the server...");
        AddServerButton("Stop", "stop", "Stopping the server...");
        AddServerButton("Restart", "restart", "Restarting the server...");
        AddServerButton("Refresh status", "status", "Checking server status...");
        serverLayout.Controls.Add(status);
        serverLayout.Controls.Add(controls);
        server.Controls.Add(serverLayout);
        layout.Controls.Add(server);

        var game = new GroupBox { Text = "Play on this PC", Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(12) };
        var gameLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, AutoSize = true };
        playControls = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        play = CreateButton("Play", async () => await Connect(true));
        playControls.Controls.Add(play);
        playControls.Controls.Add(CreateButton("Choose client...", ChooseClient));
        playControls.Controls.Add(CreateButton("Check connection", async () => await Connect(false)));
        clientStatus = new Label { AutoSize = true, MaximumSize = new Size(545, 0) };
        connectionStatus = new Label { AutoSize = true, MaximumSize = new Size(545, 0) };
        clientLoginStatus = new Label { AutoSize = true, MaximumSize = new Size(545, 0), Visible = false };
        gameLayout.Controls.Add(clientStatus);
        gameLayout.Controls.Add(playControls);
        gameLayout.Controls.Add(connectionStatus);
        gameLayout.Controls.Add(clientLoginStatus);
        game.Controls.Add(gameLayout);
        layout.Controls.Add(game);

        var login = new GroupBox { Text = "Local game login", Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(12) };
        var loginLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, AutoSize = true };
        loginLayout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        loginLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        loginLayout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        account = new TextBox { ReadOnly = true, Dock = DockStyle.Fill, AccessibleName = "Local game account" };
        password = new TextBox { ReadOnly = true, Dock = DockStyle.Fill, UseSystemPasswordChar = true, AccessibleName = "Local game password" };
        copyAccount = CreateButton("Copy account", () => CopyLoginField(account, "Account copied."));
        copyPassword = CreateButton("Copy password", () => CopyLoginField(password, "Password copied."));
        showPassword = new CheckBox { Text = "Show password", AutoSize = true };
        showPassword.CheckedChanged += (sender, args) => password.UseSystemPasswordChar = !showPassword.Checked;
        loginStatus = new Label { AutoSize = true, Margin = new Padding(3, 6, 3, 3) };
        loginLayout.Controls.Add(new Label { Text = "Account", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        loginLayout.Controls.Add(account, 1, 0);
        loginLayout.Controls.Add(copyAccount, 2, 0);
        loginLayout.Controls.Add(new Label { Text = "Password", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 1);
        loginLayout.Controls.Add(password, 1, 1);
        loginLayout.Controls.Add(copyPassword, 2, 1);
        loginLayout.Controls.Add(showPassword, 1, 2);
        loginLayout.Controls.Add(loginStatus, 0, 3);
        loginLayout.SetColumnSpan(loginStatus, 3);
        login.Controls.Add(loginLayout);
        layout.Controls.Add(login);

        var folders = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, Padding = new Padding(0, 5, 0, 0) };
        folders.Controls.Add(CreateButton("Open server logs", () => OpenFolder(Path.Combine(root, "server", "logs"))));
        folders.Controls.Add(CreateButton("Open game folder", () => OpenFolder(
            clientPath == null ? DefaultGameFolder : Path.GetDirectoryName(clientPath))));
        layout.Controls.Add(folders);

        Shown += async (sender, args) =>
        {
            LoadClient();
            LoadLogin();
            await RunServerAction("status", "Checking server status...");
        };
        Deactivate += (sender, args) => showPassword.Checked = false;
        FormClosing += (sender, args) =>
        {
            if (busy)
            {
                args.Cancel = true;
                return;
            }
            if (clientMonitor != null)
            {
                args.Cancel = true;
                closing = true;
                clientCancellation.Cancel();
                return;
            }
            password.Clear();
        };
    }

    private string DefaultGameFolder
    {
        get { return Path.Combine(Path.GetDirectoryName(root), "World of Warcraft", "_forever_"); }
    }

    private string ClientSelectionFile
    {
        get { return Path.Combine(root, "tools", "config", "local-client.txt"); }
    }

    private void LoadClient()
    {
        try
        {
            if (File.Exists(ClientSelectionFile))
            {
                string savedPath = File.ReadAllText(ClientSelectionFile).Trim();
                if (RealmConnection.IsClientExecutable(savedPath))
                    clientPath = savedPath;
            }
            if (clientPath == null)
            {
                string previousSelection = Path.Combine(root, "tools", "config", "client.txt");
                string gameFolder = File.Exists(previousSelection)
                    ? File.ReadAllText(previousSelection).Trim()
                    : Path.GetDirectoryName(DefaultGameFolder);
                if (Path.IsPathRooted(gameFolder))
                {
                    foreach (string folder in new[] { gameFolder, Path.Combine(gameFolder, "_forever_"), Path.Combine(gameFolder, "_classic_beta_") })
                    {
                        string wow = Path.Combine(folder, "Wow.exe");
                        string wowBeta = Path.Combine(folder, "WowB.exe");
                        if (RealmConnection.IsClientExecutable(wow))
                            clientPath = wow;
                        else if (RealmConnection.IsClientExecutable(wowBeta))
                            clientPath = wowBeta;
                        if (clientPath != null)
                            break;
                    }
                }
            }
        }
        catch (IOException)
        {
            connectionStatus.Text = "Could not read the saved client selection.";
        }
        catch (UnauthorizedAccessException)
        {
            connectionStatus.Text = "Could not read the saved client selection.";
        }
        ShowClient();
    }

    private void ShowClient()
    {
        clientStatus.Text = clientPath ?? "Choose the installed Forever or Classic beta client.";
        play.Enabled = clientPath != null && clientMonitor == null;
    }

    private void ChooseClient()
    {
        using (var dialog = new OpenFileDialog
        {
            Title = "Choose the Forever or Classic beta client",
            InitialDirectory = clientPath == null ? DefaultGameFolder : Path.GetDirectoryName(clientPath),
            Filter = "Forever client (Wow.exe; WowB.exe)|Wow.exe;WowB.exe",
            CheckFileExists = true,
        })
        {
            if (dialog.ShowDialog(this) != DialogResult.OK || !RealmConnection.IsClientExecutable(dialog.FileName))
                return;
            clientPath = dialog.FileName;
        }

        ShowClient();
        connectionStatus.Text = "";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(ClientSelectionFile));
            File.WriteAllText(ClientSelectionFile, clientPath);
        }
        catch (IOException)
        {
            connectionStatus.Text = "Client selected for this session. Could not save the selection.";
        }
        catch (UnauthorizedAccessException)
        {
            connectionStatus.Text = "Client selected for this session. Could not save the selection.";
        }
    }

    private async Task Connect(bool launch)
    {
        if (busy || (launch && clientMonitor != null))
            return;
        SetBusy(true);
        connectionStatus.Text = "Checking local realm connection...";
        try
        {
            string serverStatus = await Task.Run(() => RunController("status"));
            status.Text = serverStatus;
            if (serverStatus != "Server ready.")
            {
                connectionStatus.Text = "Start the local server and wait for Server ready.";
                return;
            }

            int regionGroup = 0;
            Process client = await Task.Run(() =>
            {
                RealmConnection.VerifyLocalTls();
                if (!launch)
                    return null;
                regionGroup = ClientLoginKey.ReadRegionGroup(root);
                return RealmConnection.StartClient(clientPath);
            });
            connectionStatus.Text = "Local login server passed Windows TLS validation.";
            if (client != null)
                WatchClient(client, regionGroup);
        }
        catch (RealmConnectionException ex)
        {
            connectionStatus.Text = ex.Message;
        }
        catch (Exception)
        {
            connectionStatus.Text = "Could not check the local server. Check the server status and logs.";
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async void WatchClient(Process client, int regionGroup)
    {
        clientCancellation = new CancellationTokenSource();
        clientLoginStatus.Text = "Client opened. Sign in with your local game account.";
        clientLoginStatus.Visible = true;
        CancellationToken cancellation = clientCancellation.Token;
        var progress = new Progress<string>(message =>
        {
            if (!closing && clientMonitor != null)
                clientLoginStatus.Text = message;
        });
        clientMonitor = Task.Run(() =>
        {
            using (client)
                ClientLoginKey.Monitor(client, regionGroup, cancellation, progress);
        });
        ShowClient();
        try
        {
            await clientMonitor;
            clientLoginStatus.Text = "The game was closed.";
        }
        catch (OperationCanceledException)
        {
            if (!closing)
                clientLoginStatus.Text = "The local realm key check stopped.";
        }
        catch (RealmConnectionException ex)
        {
            clientLoginStatus.Text = ex.Message;
        }
        catch (Exception)
        {
            clientLoginStatus.Text = "The local realm key check failed. Close the game and try Play again.";
        }
        finally
        {
            clientMonitor = null;
            clientCancellation.Dispose();
            clientCancellation = null;
            if (closing)
                Close();
            else
                ShowClient();
        }
    }

    private void LoadLogin()
    {
        try
        {
            var data = new JavaScriptSerializer().Deserialize<Dictionary<string, string>>(
                File.ReadAllText(Path.Combine(root, "local", "secrets.json")));
            if (data == null || !data.ContainsKey("game_email") || !data.ContainsKey("game_password") ||
                string.IsNullOrWhiteSpace(data["game_email"]) || string.IsNullOrEmpty(data["game_password"]))
                throw new InvalidDataException();

            account.Text = data["game_email"];
            password.Text = data["game_password"];
        }
        catch (Exception ex)
        {
            if (!(ex is IOException || ex is UnauthorizedAccessException || ex is ArgumentException || ex is InvalidOperationException))
                throw;
            loginStatus.Text = "The local game login could not be loaded.";
            showPassword.Enabled = copyAccount.Enabled = copyPassword.Enabled = false;
        }
    }

    private void CopyLoginField(TextBox field, string confirmation)
    {
        if (field.TextLength == 0)
            return;
        try
        {
            Clipboard.SetText(field.Text);
            loginStatus.Text = confirmation;
        }
        catch (ExternalException)
        {
            loginStatus.Text = "The clipboard is busy. Try again.";
        }
    }

    private static Button CreateButton(string title, Action action)
    {
        var button = new Button { Text = title, AutoSize = true, Padding = new Padding(4, 2, 4, 2) };
        button.Click += (sender, args) => action();
        return button;
    }

    private void AddServerButton(string title, string action, string progress)
    {
        controls.Controls.Add(CreateButton(title, async () => await RunServerAction(action, progress)));
    }

    private async Task RunServerAction(string action, string progress)
    {
        if (busy)
            return;
        SetBusy(true);
        status.Text = progress;
        try
        {
            status.Text = await Task.Run(() => RunController(action));
        }
        catch (Exception)
        {
            status.Text = "Server action failed. Open the server logs for details.";
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void SetBusy(bool value)
    {
        busy = value;
        controls.Enabled = playControls.Enabled = !value;
    }

    private string RunController(string action)
    {
        string controller = Path.Combine(root, "source", "local-server", "launcher_control.py");
        var settings = new ProcessStartInfo(python, "-E -B \"" + controller + "\" " + action)
        {
            WorkingDirectory = Environment.SystemDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        settings.EnvironmentVariables["PATH"] = Environment.SystemDirectory + ";" +
            Environment.GetFolderPath(Environment.SpecialFolder.Windows) + ";" + Path.GetDirectoryName(python);
        using (Process process = Process.Start(settings))
        {
            Task<string> output = process.StandardOutput.ReadToEndAsync();
            Task<string> errors = process.StandardError.ReadToEndAsync();
            process.WaitForExit();
            Task.WaitAll(output, errors);
            if (process.ExitCode != 0)
                throw new InvalidOperationException("Server controller failed.");
            string[] lines = output.Result.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            return lines.Length == 0 ? "Server action completed." : lines[lines.Length - 1];
        }
    }

    private void OpenFolder(string path)
    {
        if (!Directory.Exists(path))
        {
            MessageBox.Show(this, "This folder could not be found.", Text);
            return;
        }
        try
        {
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Win32Exception)
        {
            MessageBox.Show(this, "Windows could not open this folder.", Text);
        }
    }
}
