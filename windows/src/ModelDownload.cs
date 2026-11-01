// THE MODEL DOWNLOAD ALWAYS RESUMES (1.11.2026): "in this app, like in any app which downloads, you just need to
// always resume downloads. Even if the user closes the application and you open, it will continue where it left off so
// the user doesn't need to do it again."
//
// The bytes go to <models>\ggml-large-v3-turbo-q5_0.bin.part, asked for with Range: bytes=<part size>- and appended. A
// dropped connection is tried again by itself (2, 4, 8 … 60 s apart) from the .part's size at that moment. A 200 instead
// of a 206 means the server starts over: the .part is emptied. When the .part holds exactly 574041195 bytes it becomes
// the .bin. At every start of the app a .part without a finished .bin continues by itself, no button pressed.
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;

namespace MantraVoiceToText
{
    public static class ModelDownload
    {
        public static string Part => Paths.Model + ".part";
        public static bool Running { get; private set; }
        public static long Have { get; private set; }
        public static long Total => Paths.ModelBytes;
        public static string State { get; private set; } = "";
        /// fired (on a worker thread) when the progress or the state changes
        public static event Action Changed;
        static CancellationTokenSource cts;
        static readonly object gate = new object();

        public static bool PartWaiting => !Ears.ModelPresent && File.Exists(Part);

        /// At the start of the app: a download that was under way goes on by itself.
        public static void ResumeIfWaiting()
        {
            if (PartWaiting) { Log.Write($"model download: a .part of {new FileInfo(Part).Length} bytes is here, going on by itself"); Start(); }
        }

        public static void Start()
        {
            lock (gate)
            {
                if (Running || Ears.ModelPresent) return;
                Running = true;
                cts = new CancellationTokenSource();
            }
            var ct = cts.Token;
            Task.Run(() => Loop(ct));
        }

        public static void Stop() { lock (gate) cts?.Cancel(); }

        static void Say(string s) { State = s; try { Changed?.Invoke(); } catch { } }

        static async Task Loop(CancellationToken ct)
        {
            int failures = 0;
            try
            {
                while (!ct.IsCancellationRequested)
                {
                    try
                    {
                        if (await Once(ct)) return;
                        failures = 0;
                    }
                    catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
                    catch (Exception e)
                    {
                        failures++;
                        int wait = (int)Math.Min(60, Math.Pow(2, failures));
                        Log.Write($"model download: stopped at {PartSize()} bytes ({e.GetType().Name}: {e.Message}); trying again in {wait} s");
                        Say($"the connection dropped at {PartSize() / 1048576} MB: trying again in {wait} s (it goes on from there)");
                        try { await Task.Delay(TimeSpan.FromSeconds(wait), ct); } catch (OperationCanceledException) { break; }
                    }
                }
                Say($"paused at {PartSize() / 1048576} of {Total / 1048576} MB: it goes on from there");
                Log.Write($"model download: paused at {PartSize()} bytes");
            }
            finally { Running = false; try { Changed?.Invoke(); } catch { } }
        }

        static long PartSize() => File.Exists(Part) ? new FileInfo(Part).Length : 0;

        /// One request, from the .part's size on; true when the model is complete.
        static async Task<bool> Once(CancellationToken ct)
        {
            long have = PartSize();
            if (have == Total) return Finish();
            if (have > Total) { Log.Write($"model download: the .part is too big ({have}), starting over"); File.Delete(Part); have = 0; }
            using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
            http.DefaultRequestHeaders.UserAgent.ParseAdd($"VoiceToTextMantra/{Paths.Version}");
            var req = new HttpRequestMessage(HttpMethod.Get, Paths.ModelUrl);
            if (have > 0) req.Headers.Range = new RangeHeaderValue(have, null);
            Log.Write($"model download: starting at {have} bytes" + (have > 0 ? $" (Range: bytes={have}-)" : ""));
            Say(have > 0 ? $"going on from {have / 1048576} MB…" : "starting…");
            using var resp = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);
            if (resp.StatusCode == HttpStatusCode.RequestedRangeNotSatisfiable)
            {
                Log.Write("model download: 416 for the range, starting over");
                File.Delete(Part);
                return false;
            }
            resp.EnsureSuccessStatusCode();
            bool append = have > 0 && resp.StatusCode == HttpStatusCode.PartialContent;
            if (have > 0 && !append) { Log.Write($"model download: the server sent {(int)resp.StatusCode}, not 206: the .part is emptied, starting over"); have = 0; }
            Have = have;
            using (var src = await resp.Content.ReadAsStreamAsync(ct))
            using (var dst = new FileStream(Part, append ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.Read))
            {
                var buf = new byte[1 << 16];
                var last = DateTime.MinValue;
                // a stall of 60 s without a byte counts as a dropped connection
                using var stall = CancellationTokenSource.CreateLinkedTokenSource(ct);
                while (true)
                {
                    stall.CancelAfter(TimeSpan.FromSeconds(60));
                    int n;
                    try { n = await src.ReadAsync(buf, stall.Token); }
                    catch (OperationCanceledException) when (!ct.IsCancellationRequested) { throw new IOException("no data for 60 s"); }
                    if (n <= 0) break;
                    await dst.WriteAsync(buf.AsMemory(0, n), ct);
                    Have += n;
                    if ((DateTime.Now - last).TotalMilliseconds > 250)
                    {
                        last = DateTime.Now;
                        await dst.FlushAsync(ct);
                        Say($"downloading: {Have / 1048576} of {Total / 1048576} MB");
                    }
                }
            }
            long size = PartSize();
            if (size == Total) return Finish();
            throw new IOException($"the connection ended at {size} of {Total} bytes");
        }

        static bool Finish()
        {
            File.Move(Part, Paths.Model, true);
            Have = Total;
            Log.Write($"model download: complete ({Total} bytes), {Paths.Model}");
            Say("ready");
            return true;
        }
    }
}
