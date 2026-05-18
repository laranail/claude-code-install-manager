// claude-code-install-manager.exe
//
// Thin Authenticode-signable launcher for claude-code-install-manager.cmd. We ship this
// alongside the .cmd because cmd / bat files cannot be Authenticode-signed in
// Windows: the signature subsystem requires a host format that carries a
// signature block (PE for EXE/DLL, the AppManifest-style end-of-file block
// for .ps1, etc.). A .cmd has no such block, so a signed wrapper is the only
// way to give users a SmartScreen-friendly entry point.
//
// Behavior:
//   * Looks for "claude-code-install-manager.cmd" in the same directory as this EXE.
//   * Re-executes it via cmd.exe /c with all forwarded arguments.
//   * Returns the .cmd's exit code as its own.
//
// Build (release / signed):
//   .\scripts\build-launcher.ps1 -CertPath C:\path\to\codesign.pfx -CertPassword (Read-Host -AsSecureString)
//
// Build (unsigned, local development):
//   .\scripts\build-launcher.ps1
//
// Targets .NET Framework 4.x (csc.exe shipped with Windows itself) so the
// resulting EXE has no extra runtime dependency on any Windows 10+ machine.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

namespace Simtabi.ClaudeCodeInstallManager
{
    internal static class Launcher
    {
        private const string CmdFileName = "claude-code-install-manager.cmd";

        private static int Main(string[] args)
        {
            try
            {
                string exePath = Assembly.GetEntryAssembly().Location;
                string exeDir = Path.GetDirectoryName(exePath);
                string cmdPath = Path.Combine(exeDir, CmdFileName);

                if (!File.Exists(cmdPath))
                {
                    Console.Error.WriteLine(
                        "claude-code-install-manager: cannot find " + CmdFileName +
                        " next to " + Path.GetFileName(exePath) + ".");
                    Console.Error.WriteLine("Expected at: " + cmdPath);
                    Console.Error.WriteLine(
                        "Re-download the release and keep both files together.");
                    return 2;
                }

                var psi = new ProcessStartInfo("cmd.exe", BuildCmdArgs(cmdPath, args))
                {
                    UseShellExecute = false,
                };

                using (var proc = Process.Start(psi))
                {
                    proc.WaitForExit();
                    return proc.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("claude-code-install-manager: launcher failed: " + ex.Message);
                return 3;
            }
        }

        // Builds the argument string for cmd.exe. Format:
        //     /c "<cmdPath>" <arg1> <arg2> ...
        // Each arg is quoted if it contains a space or a quote character;
        // embedded quotes are escaped as \".
        private static string BuildCmdArgs(string cmdPath, string[] forwarded)
        {
            var sb = new StringBuilder(256);
            sb.Append("/c ");
            AppendQuoted(sb, cmdPath);
            foreach (string arg in forwarded)
            {
                sb.Append(' ');
                AppendQuoted(sb, arg);
            }
            return sb.ToString();
        }

        private static void AppendQuoted(StringBuilder sb, string value)
        {
            if (value == null) value = string.Empty;
            bool needsQuotes = value.Length == 0
                            || value.IndexOfAny(new[] { ' ', '\t', '"' }) >= 0;
            if (!needsQuotes)
            {
                sb.Append(value);
                return;
            }
            sb.Append('"');
            foreach (char c in value)
            {
                if (c == '"') sb.Append("\\\"");
                else sb.Append(c);
            }
            sb.Append('"');
        }
    }
}
