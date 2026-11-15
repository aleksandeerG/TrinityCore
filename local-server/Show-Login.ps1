# Show only the playing account locally. Never write credentials to stdout or another file.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$secrets = Get-Content -LiteralPath (Join-Path $root 'local\secrets.json') -Raw | ConvertFrom-Json
$gameEmail = $secrets.game_email
$gamePassword = $secrets.game_password
$secrets = $null
if (!$gameEmail -or !$gamePassword) { throw 'The local playing account is missing from secrets.json.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ForeverLoginWindowNative {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
'@
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Local WoW Forever login'
$form.ClientSize = New-Object Drawing.Size(520,235)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI',10)
# A hidden PowerShell launch can hide the process's first GUI window too. Explicitly
# show the requested dialog after that first ShowWindow call; keep the console hidden.
$form.Add_Shown({
    [void][ForeverLoginWindowNative]::ShowWindow($form.Handle, 5)
    [void][ForeverLoginWindowNative]::SetForegroundWindow($form.Handle)
})
$intro = New-Object Windows.Forms.Label
$intro.Text = 'Use this local account in the game through Forever Launcher.'
$intro.SetBounds(15,15,490,30)
$form.Controls.Add($intro)
$emailLabel = New-Object Windows.Forms.Label
$emailLabel.Text = 'Account'
$emailLabel.SetBounds(15,58,85,25)
$form.Controls.Add($emailLabel)
$emailBox = New-Object Windows.Forms.TextBox
$emailBox.Text = $gameEmail
$emailBox.ReadOnly = $true
$emailBox.SetBounds(105,55,275,28)
$form.Controls.Add($emailBox)
$copyEmail = New-Object Windows.Forms.Button
$copyEmail.Text = 'Copy account'
$copyEmail.SetBounds(390,54,115,30)
$copyEmail.Add_Click({ [Windows.Forms.Clipboard]::SetText($emailBox.Text) })
$form.Controls.Add($copyEmail)
$passwordLabel = New-Object Windows.Forms.Label
$passwordLabel.Text = 'Password'
$passwordLabel.SetBounds(15,103,85,25)
$form.Controls.Add($passwordLabel)
$passwordBox = New-Object Windows.Forms.TextBox
$passwordBox.Text = $gamePassword
$passwordBox.ReadOnly = $true
$passwordBox.UseSystemPasswordChar = $true
$passwordBox.SetBounds(105,100,275,28)
$form.Controls.Add($passwordBox)
$copyPassword = New-Object Windows.Forms.Button
$copyPassword.Text = 'Copy password'
$copyPassword.SetBounds(390,99,115,30)
$copyPassword.Add_Click({ [Windows.Forms.Clipboard]::SetText($passwordBox.Text) })
$form.Controls.Add($copyPassword)
$showPassword = New-Object Windows.Forms.CheckBox
$showPassword.Text = 'Show password'
$showPassword.SetBounds(105,140,185,25)
$showPassword.Add_CheckedChanged({ $passwordBox.UseSystemPasswordChar = !$showPassword.Checked })
$form.Controls.Add($showPassword)
$note = New-Object Windows.Forms.Label
$note.Text = 'Server: trinity.actual.battle.net (127.0.0.1). Copy only when needed.'
$note.SetBounds(15,180,490,40)
$form.Controls.Add($note)
try { $null = $form.ShowDialog() } finally { $form.Dispose(); $gamePassword = $null }
