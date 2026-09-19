using Microsoft.Win32;
using System;
using System.Diagnostics;
using System.IO;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;

namespace ClientNet;

/// <summary>
/// Enhanced Watchdog component with TLS support and comprehensive hardening:
/// - Disables Task Manager (RegEdit, cmd, taskmgr)
/// - Disables Control Panel
/// - TLS-encrypted WebSocket connection
/// - Certificate pinning for server validation
/// - Watchdog loop to re-apply restrictions if disabled
/// </summary>
public static class Watchdog
{
    // Registry keys for disabling Task Manager and RegEdit
    private const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Policies";
    private const string SystemKey = @"Software\Microsoft\Windows\CurrentVersion\Policies\System";

    // TLS configuration
    private const string ClientCertificateThumbprint = "E3A5C4D2F1B0A2C3E5D6F7A8B9C0D1E2F3A4B5C6"; // Thumbprint of trusted server cert
    private const SslProtocols SslProtocol = SslProtocols.Tls12 | SslProtocols.Tls13;

    /// <summary>
    /// Enable strict user restrictions - disable Task Manager, RegEdit, Control Panel
    /// </summary>
    public static void EnableRestrictions()
    {
        try
        {
            using (var key = Registry.CurrentUser.CreateSubKey(RegistryPath))
            {
                // Disable Task Manager (1 = enabled restriction)
                key.SetValue("DisableTaskMgr", 1, RegistryValueKind.DWord);
                Console.WriteLine("[Watchdog] Task Manager disabled via registry");

                // Disable Run dialog
                key.SetValue("NoRun", 1, RegistryValueKind.DWord);
                Console.WriteLine("[Watchdog] Run dialog disabled");
            }

            using (var key = Registry.CurrentUser.CreateSubKey(SystemKey))
            {
                // Disable Registry Tools (RegEdit, etc.)
                key.SetValue("DisableRegistryTools", 1, RegistryValueKind.DWord);
                Console.WriteLine("[Watchdog] Registry Tools disabled via system key");
            }

            // Disable Control Panel
            using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"))
            {
                key.SetValue("NoControlPanel", 1, RegistryValueKind.DWord);
                Console.WriteLine("[Watchdog] Control Panel disabled");
            }

            // Disable command prompt
            using (var key = Registry.CurrentUser.CreateSubKey(RegistryPath + "\\System"))
            {
                key.SetValue("DisableCMD", 1, RegistryValueKind.DWord);
                Console.WriteLine("[Watchdog] Command Prompt disabled");
            }

            Console.WriteLine("[Watchdog] All restrictions enabled - applied at " + DateTime.Now.ToString("HH:mm:ss"));
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Watchdog] Error enabling restrictions: {ex.Message}");
        }
    }

    /// <summary>
    /// Disable specific executable paths
    /// </summary>
    public static void DisableExecutables()
    {
        try
        {
            using (var key = Registry.CurrentUser.CreateSubKey(RegistryPath))
            {
                using (var subKey = key.CreateSubKey("System"))
                {
                    // List of executables to block
                    var blockedExes = new[] { "taskmgr.exe", "regedit.exe", "cmd.exe", "control.exe", "msconfig.exe" };

                    foreach (var exe in blockedExes)
                    {
                        subKey.SetValue($"DisableExecute_{exe}", 1, RegistryValueKind.DWord);
                        Console.WriteLine($"[Watchdog] Blocked executable: {exe}");
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Watchdog] Error disabling executables: {ex.Message}");
        }
    }

    /// <summary>
    /// Verify and enforce TLS certificate pinning for WebSocket connection
    /// </summary>
    /// <param remoteCert">Remote certificate to verify</param>
    /// <returns>true if certificate matches pinning policy</returns>
    public static bool VerifyCertificatePinning(X509Certificate2 remoteCert)
    {
        try
        {
            if (remoteCert == null) return false;

            var remoteThumbprint = remoteCert.Thumbprint;
            // Convert to uppercase for comparison
            var expected = ClientCertificateThumbprint.ToUpperInvariant();
            var actual = remoteThumbprint.ToUpperInvariant();

            bool match = actual == expected;

            if (match)
            {
                Console.WriteLine($"[TLS] Certificate pinning verified: {actual}");
            }
            else
            {
                Console.WriteLine($"[TLS] Certificate pinning FAILED! Expected: {expected}, Actual: {actual}");
            }

            return match;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[TLS] Error verifying certificate: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Enforce TLS on Socket connection
    /// </summary>
    public static void EnforceTls()
    {
        // Set global TLS settings for the application
        System.Net.ServicePointManager.SecurityProtocolType = SslProtocol;
        System.Net.ServicePointManager.ServerCertificateValidationCallback = (sender, certificate, chain, errors) =>
        {
            // Custom validation with pinning
            var cert2 = certificate as System.Security.Cryptography.X509Certificates.X509Certificate2;
            return VerifyCertificatePinning(cert2);
        };

        Console.WriteLine("[TLS] TLS 1.2/1.3 enforced - certificate pinning active");
    }

    /// <summary>
    /// Lock workstation immediately
    /// </summary>
    public static void LockWorkstation()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "rundll32.exe",
                Arguments = "user32.dll,LockWorkStation",
                UseShellExecute = false,
                CreateNoWindow = true
            };

            Process.Start(psi);
            Console.WriteLine("[Watchdog] Workstation locked");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Watchdog] Error locking workstation: {ex.Message}");
        }
    }

    /// <summary>
    /// Watchdog loop - continuously monitor and re-apply restrictions
    /// </summary>
    /// <param name="ct">Cancellation token</param>
    public static void StartWatchdogLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                Thread.Sleep(30000); // Check every 30 seconds
                ReApplyRestrictions();
                EnforceTls(); // Re-apply TLS settings
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex)
            {
                Console.WriteLine($"[Watchdog loop error] {ex.Message}");
                Thread.Sleep(5000);
            }
        }
    }

    /// <summary>
    /// Re-apply all restrictions (call from watchdog loop)
    /// </summary>
    public static void ReApplyRestrictions()
    {
        try
        {
            EnableRestrictions();
            DisableExecutables();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Watchdog re-apply error] {ex.Message}");
        }
    }

    /// <summary>
    /// Secure WebSocket client configuration with TLS
    /// </summary>
    public static async Task<ClientWebSocket> CreateSecureWebSocket(string serverUrl)
    {
        var ws = new ClientWebSocket();

        // Configure TLS settings
        ws.Options.SslProtocols = SslProtocol;
        ws.Options.ServerCertificateValidationCallback = (sender, certificate, chain, errors) =>
        {
            // Try to get the certificate and verify with pinning
            try
            {
                var cert2 = certificate as System.Security.Cryptography.X509Certificates.X509Certificate2;
                if (cert2 != null)
                {
                    return VerifyCertificatePinning(cert2);
                }
            }
            catch { }
            // Fallback: allow if pinning fails (for development)
            return errors == SslPolicyErrors.None;
        };

        // Connect to server
        try
        {
            await ws.ConnectAsync(new Uri(serverUrl), CancellationToken.None);
            Console.WriteLine($"[Secure WS] Connected to: {serverUrl}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Secure WS] Connection error: {ex.Message}");
            throw;
        }

        return ws;
    }
}