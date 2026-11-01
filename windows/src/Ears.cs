// Hearing: Whisper large-v3-turbo (q5_0) on this PC through whisper.cpp (Whisper.net), offline. The model is loaded once,
// at the first take (it starts loading the moment a take starts, while the speaker talks) and stays loaded.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Whisper.net;

namespace MantraVoiceToText
{
    public static class Ears
    {
        static WhisperFactory factory;
        static Task loading;
        static readonly object gate = new object();
        public static string LoadError { get; private set; }

        /// What Whisper writes for a take with no speech in it (it learned them from subtitles); alone, they are dropped.
        static readonly HashSet<string> inventions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        { "you", "thank you", "thank you.", "thanks for watching", "thanks for watching!", "bye", "hvala", "hvala.", "hvala vam",
          "hvala na gledanju", ".", "" };

        /// whisper.cpp's DLLs need the Microsoft Visual C++ runtime (msvcp140, vcruntime140; vcruntime140_1 on x64).
        public static bool VcRuntimeMissing
        {
            get
            {
                var need = new System.Collections.Generic.List<string> { "msvcp140.dll", "vcruntime140.dll" };
                if (System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.X64) need.Add("vcruntime140_1.dll");
                foreach (var d in need)
                {
                    if (!System.Runtime.InteropServices.NativeLibrary.TryLoad(d, out var h)) return true;
                    System.Runtime.InteropServices.NativeLibrary.Free(h);
                }
                return false;
            }
        }
        public static string VcRuntimeUrl => "https://aka.ms/vs/17/release/vc_redist." +
            (System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "arm64" : "x64") + ".exe";
        public const string VcRuntimeSay = "Whisper needs the Microsoft Visual C++ runtime: ⚙ → Settings → Get it";

        public static bool ModelPresent => File.Exists(Paths.Model) && new FileInfo(Paths.Model).Length > 100_000_000;

        /// Start loading the model in the background (once); a take waits for it.
        public static Task Warm()
        {
            lock (gate)
            {
                if (factory != null) return Task.CompletedTask;
                if (loading != null && !loading.IsFaulted) return loading;
                LoadError = null;
                loading = Task.Run(() =>
                {
                    var t0 = DateTime.Now;
                    try
                    {
                        var f = WhisperFactory.FromPath(Paths.Model, new WhisperFactoryOptions { UseFlashAttention = true });
                        lock (gate) factory = f;
                        Log.Write($"whisper: model loaded in {(DateTime.Now - t0).TotalSeconds:0.0} s ({WhisperFactory.GetRuntimeInfo()})");
                    }
                    catch (Exception e) { LoadError = e.Message; Log.Write("whisper: the model did not load: " + e); throw; }
                });
                return loading;
            }
        }

        public sealed class Heard { public string Text; public string Language; public string Error; }

        public static async Task<Heard> Hear(float[] samples, string language, CancellationToken ct)
        {
            if (!ModelPresent) return new Heard { Error = "no Whisper model yet: ⚙ → Download the model (547 MB)" };
            if (VcRuntimeMissing) return new Heard { Error = VcRuntimeSay };
            try { await Warm(); }
            catch (Exception e) { return new Heard { Error = "Whisper did not load: " + e.Message }; }
            WhisperFactory f; lock (gate) f = factory;
            var b = f.CreateBuilder()
                     .WithThreads(Math.Max(1, Math.Min(8, Environment.ProcessorCount)))
                     .WithNoContext();
            b = language == "auto" ? b.WithLanguageDetection() : b.WithLanguage(language);
            using var p = b.Build();
            var sb = new StringBuilder();
            string lang = language;
            await foreach (var seg in p.ProcessAsync(samples, ct))
            {
                sb.Append(seg.Text);
                if (!string.IsNullOrEmpty(seg.Language)) lang = seg.Language;
            }
            var text = Clean(sb.ToString());
            if (inventions.Contains(text)) return new Heard { Error = $"nothing said (Whisper heard only \"{text}\")", Language = lang };
            return new Heard { Text = text, Language = lang };
        }

        // [BLANK_AUDIO], (music) and the like are Whisper's notes, not words
        static string Clean(string s)
        {
            s = Regex.Replace(s, @"\[[^\]]*\]|\((?:music|applause|silence|laughs?)\)", " ", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\s+", " ").Trim();
            return s;
        }
    }
}
