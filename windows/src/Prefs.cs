// The settings, the key, the log and the history of Voice to Text (Mantra) (Windows; called Mantra Voice to Text in v1).
// Everything lives in %LOCALAPPDATA%\Voice to Text (Mantra): settings.json, key.bin (DPAPI, this Windows user only),
// history.json, log.txt and models\.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace MantraVoiceToText
{
    public static class Paths
    {
        public const string Name = "Voice to Text (Mantra)";
        public const int Version = 6;
        public const string OldName = "Mantra Voice to Text";             // v1's name and data folder
        public static readonly string Home = HomeFolder();
        public static string Moved { get; private set; }                  // what happened to v1's folder, for the log

        // v2: v1's folder (the model, a .part, the key, the settings, the history) is moved to the new name once, at the
        // first start; if it cannot be moved (v1 still running), v1's folder is used as it is, so nothing is downloaded again
        static string HomeFolder()
        {
            var la = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string home = Path.Combine(la, Name), old = Path.Combine(la, OldName);
            if (Directory.Exists(old) && !Directory.Exists(home))
            {
                try { Directory.Move(old, home); Moved = $"moved {old} to {home}"; }
                catch (Exception e) { Moved = $"could not move {old} ({e.Message}): using it as it is"; return old; }
            }
            return home;
        }
        public static readonly string Models = Path.Combine(Home, "models");
        public const string ModelFile = "ggml-large-v3-turbo-q5_0.bin";
        public const string ModelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin";
        public const long ModelBytes = 574041195;          // 547 MB, the size Hugging Face serves
        public static string Model => Path.Combine(Models, ModelFile);
        public static string Settings => Path.Combine(Home, "settings.json");
        public static string Key => Path.Combine(Home, "key.bin");
        public static string History => Path.Combine(Home, "history.json");
        public static string LogFile => Path.Combine(Home, "log.txt");
        static Paths() { Directory.CreateDirectory(Home); Directory.CreateDirectory(Models); }
    }

    public static class Log
    {
        static readonly object gate = new object();
        public static void Write(string s)
        {
            try
            {
                lock (gate)
                {
                    var fi = new FileInfo(Paths.LogFile);
                    if (fi.Exists && fi.Length > 2_000_000) File.Move(Paths.LogFile, Paths.LogFile + ".old", true);
                    File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "  " + s + Environment.NewLine);
                }
            }
            catch { }
        }
    }

    /// The choices, kept as JSON. Language: auto / en / hr. AutoCorrect: none / haiku / sonnet / opus. StyleEngine: haiku /
    /// sonnet / opus (never none).
    public sealed class Prefs
    {
        public string Language { get; set; } = "auto";
        public string AutoCorrect { get; set; } = "haiku";
        public string StyleEngine { get; set; } = "haiku";
        public string Extra { get; set; } = "";
        public string Microphone { get; set; } = "";         // "" = the Windows default
        public string Hotkey { get; set; } = "F1";
        public bool AfterHide { get; set; } = true;
        public bool Duck { get; set; } = true;              // v3: the speakers at 6 % while listening
        public bool LineBelow { get; set; } = false;
        public bool SettingsOnTop { get; set; } = false;
        public double? X { get; set; }
        public double? Y { get; set; }
        public Dictionary<string, string> ModelIds { get; set; } = new Dictionary<string, string>();
        public Dictionary<string, DateTime> ModelIdsAt { get; set; } = new Dictionary<string, DateTime>();

        public static Prefs Current { get; private set; } = Load();

        static Prefs Load()
        {
            try { if (File.Exists(Paths.Settings)) return JsonSerializer.Deserialize<Prefs>(File.ReadAllText(Paths.Settings)) ?? new Prefs(); }
            catch (Exception e) { Log.Write("settings unreadable, defaults: " + e.Message); }
            return new Prefs();
        }

        public void Save()
        {
            try { File.WriteAllText(Paths.Settings, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true })); }
            catch (Exception e) { Log.Write("settings not saved: " + e.Message); }
        }

        public static string LanguageTitle(string l) => l == "en" ? "English" : l == "hr" ? "Croatian" : "Auto (Whisper finds the language)";
        public static string EngineTitle(string e) => e switch { "haiku" => "Claude Haiku", "sonnet" => "Claude Sonnet", "opus" => "Claude Opus", _ => "None" };
    }

    /// The Anthropic key: typed once into ⚙, kept with DPAPI (CurrentUser scope), never shown again, never logged.
    public static class ApiKey
    {
        public static bool Has => File.Exists(Paths.Key);

        public static string Get()
        {
            try
            {
                if (!File.Exists(Paths.Key)) return null;
                var plain = Dpapi.Unprotect(File.ReadAllBytes(Paths.Key));
                var s = Encoding.UTF8.GetString(plain).Trim();
                return s.Length == 0 ? null : s;
            }
            catch { return null; }
        }

        public static void Set(string key)
        {
            key = (key ?? "").Trim();
            if (key.Length == 0) { Forget(); return; }
            File.WriteAllBytes(Paths.Key, Dpapi.Protect(Encoding.UTF8.GetBytes(key)));
        }

        public static void Forget() { try { File.Delete(Paths.Key); } catch { } }
    }

    static class Dpapi
    {
        [StructLayout(LayoutKind.Sequential)]
        struct Blob { public int Size; public IntPtr Data; }
        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CryptProtectData(ref Blob input, string desc, IntPtr entropy, IntPtr reserved, IntPtr prompt, int flags, ref Blob output);
        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CryptUnprotectData(ref Blob input, IntPtr desc, IntPtr entropy, IntPtr reserved, IntPtr prompt, int flags, ref Blob output);
        [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
        const int UI_FORBIDDEN = 1;

        static byte[] Run(byte[] data, bool protect)
        {
            var input = new Blob { Size = data.Length, Data = Marshal.AllocHGlobal(Math.Max(1, data.Length)) };
            var output = new Blob();
            try
            {
                Marshal.Copy(data, 0, input.Data, data.Length);
                bool ok = protect ? CryptProtectData(ref input, Paths.Name, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, UI_FORBIDDEN, ref output)
                                  : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, UI_FORBIDDEN, ref output);
                if (!ok) throw new InvalidOperationException("DPAPI error " + Marshal.GetLastWin32Error());
                var r = new byte[output.Size];
                Marshal.Copy(output.Data, r, 0, output.Size);
                return r;
            }
            finally
            {
                Marshal.FreeHGlobal(input.Data);
                if (output.Data != IntPtr.Zero) LocalFree(output.Data);
            }
        }
        public static byte[] Protect(byte[] d) => Run(d, true);
        public static byte[] Unprotect(byte[] d) => Run(d, false);
    }

    public sealed class Take
    {
        public DateTime At { get; set; }
        public string Heard { get; set; } = "";
        public string Text { get; set; } = "";
        public string Language { get; set; } = "";
        public string Correction { get; set; } = "";
        public double Seconds { get; set; }
    }

    /// The last 100 takes, newest first.
    public static class History
    {
        static List<Take> items = Load();
        static List<Take> Load()
        {
            try { if (File.Exists(Paths.History)) return JsonSerializer.Deserialize<List<Take>>(File.ReadAllText(Paths.History)) ?? new List<Take>(); }
            catch { }
            return new List<Take>();
        }
        public static IReadOnlyList<Take> Items => items;
        public static void Add(Take t)
        {
            items.Insert(0, t);
            if (items.Count > 100) items = items.Take(100).ToList();
            try { File.WriteAllText(Paths.History, JsonSerializer.Serialize(items, new JsonSerializerOptions { WriteIndented = true })); } catch { }
        }
        public static void Clear() { items.Clear(); try { File.Delete(Paths.History); } catch { } }
    }
}
