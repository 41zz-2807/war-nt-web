using System;
using System.Configuration;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace ClientNet;

class Program
{
    private static readonly string ServerUrl = ConfigurationManager.AppSettings["ServerUrl"]
        ?? "ws://localhost:3000/socket.io/";
    private static readonly string PcToken = ConfigurationManager.AppSettings["Token"] ?? "";
    private static ClientWebSocket? _ws;
    private static TimeSpan _remainingTime = TimeSpan.Zero;
    private static DateTime _lastHeartbeat = DateTime.UtcNow;
    private const int HeartbeatIntervalSeconds = 20;
    private const int IdleTimeoutSeconds = 300; // 5 menit

    static async Task Main(string[] args)
    {
        Console.WriteLine("=== Warnet Client Agent ===");
        Console.WriteLine($"PC ID: {Environment.MachineName}");
        Console.WriteLine($"Connecting to: {ServerUrl}");
        Console.WriteLine($"Token: {(string.IsNullOrEmpty(PcToken) ? "(KOSONG - ambil dari dashboard kasir)" : PcToken.Substring(0, Math.Min(6, PcToken.Length)) + "...")}");

        try
        {
            await ConnectAndRunAsync();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Fatal error: {ex.Message}");
            Environment.Exit(1);
        }
    }

    static async Task ConnectAndRunAsync()
    {
        _ws = new ClientWebSocket();

        using var cts = new CancellationTokenSource();

        await _ws.ConnectAsync(new Uri(ServerUrl), cts.Token);

        // Kirim Socket.IO v4 CONNECT packet beserta token auth
        // Format: Engine.IO type '4' + SI connect type '0' + namespace/'/' + json {"auth":{...}}
        var authJson = string.IsNullOrEmpty(PcToken)
            ? "{}"
            : "{\"token\":\"" + PcToken + "\"}";
        var connectPacket = "40" + "{\"auth\":" + authJson + "}";
        await _ws.SendAsync(
            new ArraySegment<byte>(Encoding.UTF8.GetBytes(connectPacket)),
            System.Net.WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        Console.WriteLine("Socket.IO connect packet terkirim (auth token).");

        // Heartbeat task
        _ = Task.Run(async () =>
        {
            while (_ws?.State == System.Net.WebSocketState.Open)
            {
                await Task.Delay(HeartbeatIntervalSeconds * 1000, cts.Token);
                try
                {
                    if (_ws.State == System.Net.WebSocketState.Open)
                    {
                        var payload = $"2::{DateTime.UtcNow.ToString("o")}";
                        await _ws.SendAsync(
                            new ArraySegment<byte>(Encoding.UTF8.GetBytes(payload)),
                            System.Net.WebSocketMessageType.Text,
                            true,
                            CancellationToken.None);
                    }
                }
                catch { /* ignore heartbeat errors */ }
            }
        }, cts.Token);

        // Receive messages
        var buffer = new byte[4096];
        while (_ws?.State == System.Net.WebSocketState.Open)
        {
            var result = await _ws.ReceiveAsync(buffer, cts.Token);
            if (result.MessageType == System.Net.WebSocketMessageType.Close)
            {
                await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Client shutting down", cts.Token);
                break;
            }

            var message = Encoding.UTF8.GetString(buffer, 0, result.Count);
            await HandleMessageAsync(message);
        }

        await Task.Delay(1000, cts.Token);
    }

    static async Task HandleMessageAsync(string message)
    {
        // Socket.IO format: 42[event] or 42["event",data]
        if (message.StartsWith("42"))
        {
            var payload = message.Substring(2);
            try
            {
                await ProcessSocketIoMessageAsync(payload);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error processing message: {ex.Message}");
            }
        }
    }

    static async Task ProcessSocketIoMessageAsync(string payload)
    {
        // Parse: event_name,data
        var commaIdx = payload.IndexOf(',');
        if (commaIdx < 0) return;

        var eventName = payload.Substring(0, commaIdx);
        var data = payload.Substring(commaIdx + 1);

        switch (eventName)
        {
            case "pc:status":
                await HandlePcStatusAsync(data);
                break;
            case "timer:update":
                await HandleTimerUpdateAsync(data);
                break;
            case "session:started":
                await HandleSessionStartedAsync(data);
                break;
            case "session:stopped":
                await HandleSessionStoppedAsync(data);
                break;
        }
    }

    static async Task HandlePcStatusAsync(string data)
    {
        // data: {"status":"online","socketId":"abc123"}
        try
        {
            dynamic? dyn = System.Text.Json.JsonSerializer.Deserialize<object>(data);
            var status = dyn?.status ?? "unknown";
            var socketId = dyn?.socketId ?? "";

            Console.WriteLine($"[PC Status] {status} (socket: {socketId})");

            if (status == "online")
            {
                // Lock screen - prevent user from interacting while billing session is active
                await LockScreenAsync();
            }
            else
            {
                Console.WriteLine("PC disconnected - unlocking screen");
            }
        }
        catch { }
    }

    static async Task HandleTimerUpdateAsync(string data)
    {
        // data: {"pc_id":"pc001","remainingTime":"00:15:00","isActive":true}
        try
        {
            // Parse remaining time format "HH:mm:ss" or "mm:ss"
            var remaining = ParseTimeSpan(data);
            _remainingTime = remaining;

            // Display timer
            var timeStr = remaining.ToString(@"mm\:ss");
            Console.WriteLine($"[Timer] Waktu tersisa: {timeStr} | Status: {(remaining > TimeSpan.Zero ? "ACTIVE" : "EXPIRED")}");

            // If timer almost expired (< 1 menit), show warning
            if (remaining > TimeSpan.Zero && remaining.TotalSeconds < 60)
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"⚠️  Sisa waktu kurang dari 1 menit! (sisa: {remaining.TotalSeconds:F1}s)");
                Console.ResetColor();
            }

            // Auto-lock if time expires
            if (remaining <= TimeSpan.Zero)
            {
                await LockScreenAsync();
                Console.WriteLine("⏰ Waktu habis - layar terkunci otomatis");
            }
        }
        catch { }
    }

    static TimeSpan ParseTimeSpan(string data)
    {
        // Parse "00:15:00" or "15:00" or similar
        try
        {
            // Remove quotes if present
            data = data.Trim('"', '"');

            // Try formats: "mm:ss", "HH:mm:ss"
            if (data.Contains(':'))
            {
                var parts = data.Split(':');
                if (parts.Length == 2)
                {
                    // mm:ss format
                    if (int.TryParse(parts[0], out var min) && int.TryParse(parts[1], out var sec))
                    {
                        return TimeSpan.FromMinutes(min) + TimeSpan.FromSeconds(sec);
                    }
                }
                else if (parts.Length == 3)
                {
                    // HH:mm:ss format
                    if (int.TryParse(parts[0], out var hour) && int.TryParse(parts[1], out var min) && int.TryParse(parts[2], out var sec))
                    {
                        return TimeSpan.FromHours(hour) + TimeSpan.FromMinutes(min) + TimeSpan.FromSeconds(sec);
                    }
                }
            }

            return TimeSpan.Zero;
        }
        catch { return TimeSpan.Zero; }
    }

    static async Task HandleSessionStartedAsync(string data)
    {
        // data: {"pc_id":"pc001","user":"kasir","durationMin":30}
        try
        {
            Console.WriteLine($"[Session] Memulai billing PC: {data}");
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("💰 Sesi billing dimulai - sistem akan melacak waktu real-time");
            Console.ResetColor();

            // Start lock screen timer
            await LockScreenAsync();
        }
        catch { }
    }

    static async Task HandleSessionStoppedAsync(string data)
    {
        // data: {"pc_id":"pc001","remainingTime":"00:05:00"}
        try
        {
            Console.WriteLine($"[Session] Sesi dihentikan: {data}");
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("⏹️  Sesi billing dihentikan - sisa waktu akan diverifikasi");
            Console.ResetColor();

            // If remaining time > 0, convert to saldo (prepaid model)
            // This is handled server-side, client just notes it
        }
        catch { }
    }

    static async Task LockScreenAsync()
    {
        // Implement lock screen - blocking console input until session ends
        Console.ForegroundColor = ConsoleColor.DarkGray;
        Console.BackgroundColor = ConsoleColor.Black;
        Console.Clear();
        Console.WriteLine("=== WARNET BILLING SYSTEM ===");
        Console.WriteLine("Sesi billing aktif - layar terkunci");
        Console.WriteLine($"PC: {Environment.MachineName}");
        Console.WriteLine($"Waktu tersisa: {_remainingTime:mm\\:ss\\}");
        Console.WriteLine("Tekan Ctrl+C untuk keluar paksa");
        Console.ResetColor();

        // Block input - wait for session:end signal from server
        // In a real implementation, this would show a GUI lock screen
        await Task.Delay(Timeout.Infinite).ConfigureAwait(false);
    }
}