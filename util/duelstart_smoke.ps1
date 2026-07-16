# Multirole duel-start smoke: drives TWO headless CTOS clients through
# room creation -> deck -> ready -> start -> pregame RPS/turn prompts ->
# duel start, then pumps game messages for a few seconds. This exercises
# the exact path that crashed on 2026-07-13 (multirole.exe AV in memcpy
# right after hornet spawn) without needing a human client.
# Usage: powershell -File duelstart_smoke.ps1 [-ServerDir E:\github\Multiroptcg\run]
param([string]$ServerDir = "E:\github\Multiroptcg\run")

$source = @'
using System;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;

public static class DuelStartSmoke {
    // --- wire structs (MSVC natural alignment, little endian) ---
    [StructLayout(LayoutKind.Sequential)] public struct ClientVersion {
        public byte cMaj, cMin, coreMaj, coreMin;
    }
    [StructLayout(LayoutKind.Sequential)] public struct HostInfo {
        public uint banlistHash;
        public byte allowed, mode, duelRule, dontCheckDeckContent, dontShuffleDeck;
        public uint startingLP;              // aligned to 12 via 3B pad
        public byte startingDrawCount, drawCountPerTurn;
        public ushort timeLimitInSeconds;
        public uint duelFlagsHigh, handshake;
        public ClientVersion version;
        public int t0Count, t1Count, bestOf;
        public uint duelFlagsLow;
        public int forb;
        public ushort extraRules;
        public ushort mainMin, mainMax, extraMin, extraMax, sideMin, sideMax;
    }

    class Cli {
        public TcpClient tcp; public NetworkStream ns; public string name;
        public List<byte> inbuf = new List<byte>();
        public Cli(string n) { name = n; tcp = new TcpClient(); tcp.Connect("127.0.0.1", 7911); ns = tcp.GetStream(); tcp.NoDelay = true; }
        public void Send(byte type, byte[] payload) {
            int len = 1 + (payload == null ? 0 : payload.Length);
            var buf = new byte[2 + len];
            buf[0] = (byte)(len & 0xff); buf[1] = (byte)(len >> 8); buf[2] = type;
            if (payload != null) Array.Copy(payload, 0, buf, 3, payload.Length);
            ns.Write(buf, 0, buf.Length);
        }
        public void Pump() {
            while (tcp.Available > 0) {
                var b = new byte[tcp.Available];
                int n = ns.Read(b, 0, b.Length);
                for (int i = 0; i < n; ++i) inbuf.Add(b[i]);
            }
        }
        // returns [type, payload...] or null
        public byte[] Next() {
            Pump();
            if (inbuf.Count < 3) return null;
            int len = inbuf[0] | (inbuf[1] << 8);
            if (inbuf.Count < 2 + len) return null;
            var pkt = new byte[len];
            inbuf.CopyTo(2, pkt, 0, len);
            inbuf.RemoveRange(0, 2 + len);
            return pkt;
        }
    }

    static byte[] Struct<T>(T s) where T : struct {
        int sz = Marshal.SizeOf(typeof(T));
        var b = new byte[sz]; var p = Marshal.AllocHGlobal(sz);
        Marshal.StructureToPtr(s, p, false); Marshal.Copy(p, b, 0, sz); Marshal.FreeHGlobal(p);
        return b;
    }
    static byte[] Utf16Name(string s, int chars) {
        var b = new byte[chars * 2];
        var raw = Encoding.Unicode.GetBytes(s);
        Array.Copy(raw, b, Math.Min(raw.Length, b.Length - 2));
        return b;
    }
    static byte[] Concat(params byte[][] arrays) {
        int total = 0; foreach (var a in arrays) total += a.Length;
        var r = new byte[total]; int off = 0;
        foreach (var a in arrays) { Array.Copy(a, 0, r, off, a.Length); off += a.Length; }
        return r;
    }
    static byte[] DeckPayload() {
        var codes = new List<uint>();
        codes.Add(880000634U); // leader
        for (int i = 0; i < 45; ++i) codes.Add(880000881U);
        var b = new List<byte>();
        b.AddRange(BitConverter.GetBytes((uint)codes.Count));
        b.AddRange(BitConverter.GetBytes((uint)0)); // side
        foreach (var c in codes) b.AddRange(BitConverter.GetBytes(c));
        return b.ToArray();
    }

    public static int Run() {
        Console.WriteLine("hostinfo size=" + Marshal.SizeOf(typeof(HostInfo)) + " (expect 66-68ish)");
        var ver = new ClientVersion { cMaj = 41, cMin = 0, coreMaj = 11, coreMin = 0 };
        var hi = new HostInfo {
            banlistHash = 0, allowed = 3, mode = 0, duelRule = 0,
            dontCheckDeckContent = 1, dontShuffleDeck = 1,
            startingLP = 8000, startingDrawCount = 5, drawCountPerTurn = 1,
            timeLimitInSeconds = 0,
            duelFlagsHigh = 0x60, handshake = 4043399681U, version = ver,
            t0Count = 1, t1Count = 1, bestOf = 1, duelFlagsLow = 0x10,
            forb = 0, extraRules = 0,
            mainMin = 1, mainMax = 250, extraMin = 0, extraMax = 250, sideMin = 0, sideMax = 250
        };

        var A = new Cli("FableA");
        A.Send(0x10, Utf16Name("FableA", 20));
        A.Send(0x11, Concat(Struct(hi), Utf16Name("smoke", 20), Utf16Name("", 20), new byte[200]));

        uint roomId = 0; bool aInRoom = false;
        var t0 = Environment.TickCount;
        while (Environment.TickCount - t0 < 5000) {
            var p = A.Next();
            if (p == null) { System.Threading.Thread.Sleep(20); continue; }
            if (p[0] == 0x11) { roomId = BitConverter.ToUInt32(p, 1); Console.WriteLine("A: room id=" + roomId); }
            if (p[0] == 0x12) aInRoom = true; // STOC JoinGame
            if (p[0] == 0x13) { Console.WriteLine("A: type_change=0x" + p[1].ToString("x2")); break; }
            if (p[0] == 0x02) { Console.WriteLine("A: ERROR " + BitConverter.ToString(p)); return 2; }
        }
        if (!aInRoom && roomId == 0) { Console.WriteLine("FAIL: A never joined"); return 2; }

        var B = new Cli("FableB");
        B.Send(0x10, Utf16Name("FableB", 20));
        B.Send(0x12, Concat(new byte[] { 0, 0, 0, 0 } /* version2 u16 + pad */,
            BitConverter.GetBytes(roomId), Utf16Name("", 20), Struct(ver)));
        t0 = Environment.TickCount; bool bIn = false;
        while (Environment.TickCount - t0 < 5000) {
            var p = B.Next();
            if (p == null) { System.Threading.Thread.Sleep(20); continue; }
            if (p[0] == 0x12) bIn = true;
            if (p[0] == 0x13) { Console.WriteLine("B: type_change=0x" + p[1].ToString("x2")); break; }
            if (p[0] == 0x02) { Console.WriteLine("B: ERROR " + BitConverter.ToString(p)); return 2; }
        }
        if (!bIn) { Console.WriteLine("FAIL: B never joined room " + roomId); return 2; }

        A.Send(0x02, DeckPayload()); B.Send(0x02, DeckPayload());
        System.Threading.Thread.Sleep(150);
        A.Send(0x22, null); B.Send(0x22, null);
        System.Threading.Thread.Sleep(150);
        A.Send(0x25, null); // try start
        Console.WriteLine("TRY_START sent");

        // pregame prompts + duel pump
        int gameMsgs = 0; var seenIds = new List<byte>();
        bool aAnsweredRps = false, bAnsweredRps = false, aAnsweredOrder = false;
        bool dead = false; string deadWhy = "";
        t0 = Environment.TickCount;
        while (Environment.TickCount - t0 < 12000) {
            try {
                foreach (var c in new[] { A, B }) {
                    for (var p = c.Next(); p != null; p = c.Next()) {
                        switch (p[0]) {
                            case 0x15: Console.WriteLine(c.name + ": DUEL_START"); break;
                            case 0x03: // CHOOSE_RPS
                                if (c == A && !aAnsweredRps) { aAnsweredRps = true; c.Send(0x03, new byte[] { 2 }); Console.WriteLine("A: rps -> rock"); }
                                if (c == B && !bAnsweredRps) { bAnsweredRps = true; c.Send(0x03, new byte[] { 1 }); Console.WriteLine("B: rps -> scissors"); }
                                break;
                            case 0x04: // CHOOSE_ORDER
                                if (!aAnsweredOrder) { aAnsweredOrder = true; c.Send(0x04, new byte[] { 1 }); Console.WriteLine(c.name + ": order -> first"); }
                                break;
                            case 0x01: // GAME_MSG
                                gameMsgs++;
                                if (p.Length > 1 && seenIds.Count < 40) seenIds.Add(p[1]);
                                break;
                            case 0x02:
                                Console.WriteLine(c.name + ": STOC_ERROR " + BitConverter.ToString(p));
                                break;
                        }
                    }
                    if (c.tcp.Client.Poll(0, SelectMode.SelectRead) && c.tcp.Available == 0) {
                        dead = true; deadWhy = c.name + " socket closed by server";
                    }
                }
            } catch (Exception e) { dead = true; deadWhy = e.Message; }
            if (dead) break;
            if (gameMsgs > 25) break; // enough proof
            System.Threading.Thread.Sleep(30);
        }
        Console.WriteLine("--- verdict ---");
        Console.WriteLine("game_msgs=" + gameMsgs + " first_msg_ids=[" + string.Join(",", seenIds) + "]");
        if (dead) { Console.WriteLine("CONNECTION LOST: " + deadWhy); Console.WriteLine("DUELSTART_SMOKE FAIL"); return 1; }
        if (gameMsgs == 0) { Console.WriteLine("no game messages arrived"); Console.WriteLine("DUELSTART_SMOKE FAIL"); return 1; }
        Console.WriteLine("DUELSTART_SMOKE PASS");
        return 0;
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp

# fresh server instance with logs
Get-Process -Name multirole, hornet -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
# repo clone/pull at boot goes over https - give the server the same CA
# bundle the friend package ships, or the first boot dies on SSL.
$cacert = Join-Path $ServerDir "cacert.pem"
if (Test-Path $cacert) { $env:SSL_CERT_FILE = $cacert }
$proc = Start-Process (Join-Path $ServerDir "multirole.exe") -WorkingDirectory $ServerDir -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $ServerDir "smoke_out.log") -RedirectStandardError (Join-Path $ServerDir "smoke_err.log")
Start-Sleep -Seconds 3
if ($proc.HasExited) { Write-Host "SERVER DIED AT BOOT (exit=$($proc.ExitCode))"; Get-Content (Join-Path $ServerDir "smoke_out.log") -Tail 5; exit 2 }
# clone/pull can outlast the 3s boot nap - wait until 7911 actually listens.
$deadline = (Get-Date).AddSeconds(40)
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { Write-Host "SERVER DIED DURING BOOT (exit=$($proc.ExitCode))"; Get-Content (Join-Path $ServerDir "smoke_out.log") -Tail 5; exit 2 }
    $listening = Get-NetTCPConnection -LocalPort 7911 -State Listen -ErrorAction SilentlyContinue
    if ($listening) { break }
    Start-Sleep -Milliseconds 500
}

# 7911 starts listening BEFORE the repo clone/fetch + provider load finish,
# so a join fired at first-listen can go unanswered (observed on first boot
# and on slow fetches). Retry with breathing room instead of failing once.
$code = 1
for ($try = 1; $try -le 6; $try++) {
    $code = [DuelStartSmoke]::Run()
    if ($code -eq 0) { break }
    if ($proc.HasExited) { Write-Host "server exited between attempts"; break }
    Write-Host "attempt $try failed - server may still be loading; retrying in 10s..."
    Start-Sleep -Seconds 10
}

Start-Sleep -Milliseconds 500
$alive = -not $proc.HasExited
Write-Host "server_alive_after=$alive"
if (-not $alive) { Write-Host "SERVER CRASHED (exit=0x$('{0:x}' -f $proc.ExitCode))" }
Get-Process -Name multirole, hornet -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "--- server stdout tail ---"
Get-Content (Join-Path $ServerDir "smoke_out.log") -Tail 6 -ErrorAction SilentlyContinue
exit $code
