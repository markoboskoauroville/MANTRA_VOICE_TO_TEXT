// Voice to Text (Mantra) (Windows), v2 (v1 was called Mantra Voice to Text). The start: one copy at a time (a second start brings the blob back), the tray
// icon, and the test switches:
//   --pill-shot <dir>        the blob's faces drawn into PNGs, nothing shown on the screen, then exit
//   --take <file.wav>        a recording through the same road as a take from the microphone
//       --no-type            … written down but not typed
//       --exit               … the app quits 4 s after the take is done
//       --repeat <n>         … the same file n times (the first take loads the model, the next ones show the warm time)
//   --bands <file.wav>       the voice meter's eleven bands (dB) every 0.1 s, into the log
//   --settings-shot <png>    ⚙ Settings drawn into a PNG (the whole page under the first row), then exit
//   --download-model         starts the model download (it also goes on by itself at every start while a .part waits)
//   --settings               open ⚙ Settings at the start
//   --press <id> [s]         presses a blob button after s seconds as a click would (close, language, pause, copy,
//                            style, settings, send), without the mouse
//   --test-style-fake        STYLE writes the box back in capitals, no Claude (tests the reading and writing back)
using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace MantraVoiceToText
{
    public static class Program
    {
        static string Arg(string[] a, string name) { int i = Array.IndexOf(a, name); return i >= 0 && i + 1 < a.Length ? a[i + 1] : null; }

        [STAThread]
        public static int Main(string[] args)
        {
            AppDomain.CurrentDomain.UnhandledException += (s, e) => Log.Write("CRASH: " + e.ExceptionObject);
            var shotDir = Arg(args, "--pill-shot");
            if (shotDir != null)
            {
                try { Log.Write("--pill-shot " + shotDir); int r = PillShots(shotDir); Log.Write("--pill-shot done"); return r; }
                catch (Exception e) { Log.Write("--pill-shot failed: " + e); return 1; }
            }

            var bandsFile = Arg(args, "--bands");            // --bands <wav>: the meter's eleven bands every 0.1 s, into the log
            if (bandsFile != null)
            {
                var x = WavFile.Read16kMono(bandsFile);
                for (int i = 0; i + Bands.N <= x.Length; i += Recorder.Rate / 10)
                    Log.Write($"bands {i / (double)Recorder.Rate,5:0.0} s " + string.Join(" ", Bands.Analyse(x[i..(i + Bands.N)], Recorder.Rate).Select(v => $"{v,5:0}")));
                return 0;
            }
            if (args.Contains("--duck-test"))                // v3: the speakers to 6 % for two seconds and back, into the log
            {
                Log.Write("duck-test start");
                Log.Write($"duck-test before {Duck.Now():0.000}"); Duck.Down();
                Log.Write($"duck-test ducked {Duck.Now():0.000}"); Thread.Sleep(2000); Duck.Up();
                Log.Write($"duck-test after {Duck.Now():0.000}"); return 0;
            }
            Duck.Up();                                       // v3: speakers left at 6 % by a crash go back
            var takeFile = Arg(args, "--take");
            bool test = takeFile != null || args.Contains("--test-style-fake");
            Mutex single = null;
            EventWaitHandle show = null;
            if (!test)
            {
                single = new Mutex(true, "VoiceToTextMantra.single", out bool first);
                show = new EventWaitHandle(false, EventResetMode.AutoReset, "VoiceToTextMantra.show");
                if (!first) { show.Set(); return 0; }
            }

            if (Paths.Moved != null) Log.Write("data folder: " + Paths.Moved);
            Log.Write($"start v{Paths.Version} ({System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}, {Environment.OSVersion}) " + string.Join(" ", args));
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.DispatcherUnhandledException += (s, e) => { Log.Write("UI error: " + e.Exception); e.Handled = true; };
            var stripe = new Stripe { NoTyping = args.Contains("--no-type"), FakeStyle = args.Contains("--test-style-fake") };
            new WindowInteropHelper(stripe.Window).EnsureHandle();
            stripe.Window.ShowQuietly();

            System.Windows.Forms.NotifyIcon tray = null;
            try
            {
                tray = new System.Windows.Forms.NotifyIcon
                {
                    Text = Paths.Name, Visible = true,
                    Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath),
                    ContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(),
                };
                tray.ContextMenuStrip.Items.Add("Show the blob", null, (s, e) => stripe.Show());
                tray.ContextMenuStrip.Items.Add("Settings…", null, (s, e) => stripe.OpenSettings());
                tray.ContextMenuStrip.Items.Add("Quit " + Paths.Name, null, (s, e) => stripe.Quit());
                tray.MouseClick += (s, e) => { if (e.Button == System.Windows.Forms.MouseButtons.Left) stripe.Show(); };
            }
            catch (Exception e) { Log.Write("tray icon: " + e.Message); }

            if (show != null)
            {
                var t = new Thread(() => { while (show.WaitOne()) app.Dispatcher.BeginInvoke(new Action(stripe.Show)); }) { IsBackground = true };
                t.Start();
            }
            // a model download that was under way goes on by itself ("always resume downloads")
            bool wasDownloading = false;
            ModelDownload.Changed += () =>
            {
                bool now = ModelDownload.Running;
                if (now != wasDownloading || Ears.ModelPresent) app.Dispatcher.BeginInvoke(new Action(stripe.SettingsChanged));
                wasDownloading = now;
            };
            if (args.Contains("--download-model")) ModelDownload.Start();
            else ModelDownload.ResumeIfWaiting();
            if (args.Contains("--settings")) stripe.OpenSettings();
            var settingsShot = Arg(args, "--settings-shot");    // --settings-shot <png>: ⚙ Settings drawn into a PNG, then exit
            if (settingsShot != null)
            {
                stripe.OpenSettings();
                app.Dispatcher.BeginInvoke(new Action(async () =>
                {
                    await Task.Delay(1500);
                    var w = Application.Current.Windows.OfType<SettingsWindow>().First();
                    var dock = (System.Windows.Controls.DockPanel)w.Content;
                    var top = (FrameworkElement)dock.Children[0];
                    var el = (FrameworkElement)((System.Windows.Controls.ScrollViewer)dock.Children[1]).Content;
                    double W = Math.Max(top.ActualWidth, el.ActualWidth) + 24, H = top.ActualHeight + el.ActualHeight + 24;
                    var bmp = new System.Windows.Media.Imaging.RenderTargetBitmap((int)(W * 1.5), (int)(H * 1.5), 144, 144, PixelFormats.Pbgra32);
                    var dv = new DrawingVisual();
                    using (var dc = dv.RenderOpen())
                    {
                        dc.DrawRectangle(w.Background, null, new Rect(0, 0, W, H));
                        dc.DrawRectangle(new VisualBrush(top), null, new Rect(12, 8, top.ActualWidth, top.ActualHeight));
                        dc.DrawRectangle(new VisualBrush(el), null, new Rect(12, 8 + top.ActualHeight, el.ActualWidth, el.ActualHeight));
                    }
                    bmp.Render(dv);
                    var enc = new System.Windows.Media.Imaging.PngBitmapEncoder(); enc.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bmp));
                    using (var fs = File.Create(settingsShot)) enc.Save(fs);
                    Log.Write("--settings-shot " + settingsShot);
                    stripe.Quit();
                }));
            }
            var press = Arg(args, "--press");                 // --press <button id> [seconds]: as a click on it, no mouse
            if (press != null)
            {
                int i = Array.IndexOf(args, "--press");
                double secs = i + 2 < args.Length && double.TryParse(args[i + 2], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : 3;
                app.Dispatcher.BeginInvoke(new Action(async () =>
                {
                    await Task.Delay(TimeSpan.FromSeconds(secs));
                    var f = stripe.Window.Face;
                    var b = new[] { f.Close, f.Lang, f.Pause, f.Copy, f.StyleBtn, f.Gear, f.Send }.FirstOrDefault(x => x.Id == press);
                    Log.Write("--press " + press + (b == null ? ": no such button" : ""));
                    if (b != null && b.Live) b.Pressed?.Invoke();
                }));
            }
            if (takeFile != null)
            {
                int repeat = int.TryParse(Arg(args, "--repeat"), out var r) ? Math.Max(1, r) : 1;
                app.Dispatcher.BeginInvoke(new Action(async () =>
                {
                    await Task.Delay(500);
                    for (int i = 0; i < repeat; i++) await stripe.TakeFile(Path.GetFullPath(takeFile));
                    if (args.Contains("--exit")) { await Task.Delay(4000); stripe.Quit(); }
                }));
            }
            app.Run();
            if (tray != null) { tray.Visible = false; tray.Dispose(); }
            GC.KeepAlive(single);
            return 0;
        }

        static int PillShots(string dir)
        {
            Directory.CreateDirectory(dir);
            var line = Ink.Line;
            void Shot(string name, string text, Color colour, string send, bool pause, double[] db, bool styling = false, bool copying = false,
                      bool autoCorrect = true, bool unlanded = false, bool below = false, string lang = "AUTO")
            {
                var f = new PillFace(() => { }, () => { }, () => { }, () => { }, () => { }, () => { }, () => { });
                f.PlaceLine(below);
                f.Say(text, colour);
                f.Lang.Text = lang; f.Send.Symbol = send; f.Pause.Live = pause;
                f.Light(autoCorrect, styling, unlanded, copying);
                f.Wave.Moving = db != null; f.Wave.Take(db);
                f.SavePng(Path.Combine(dir, name)); Log.Write("  " + name);
            }
            var voice = new double[] { -40, -30, -24, -22, -26, -30, -34, -40, -46, -52, -60 };
            Shot("1-ready.png", "F1 TO TALK · WHISPER TURBO AUTO · AUTO CORRECT: CLAUDE HAIKU", line, "", false, null);
            Shot("2-recording.png", "● 0:07 · WHISPER TURBO AUTO · AUTO CORRECT: CLAUDE HAIKU", Ink.Red, "", true, voice);
            Shot("3-writing.png", "⠹ writing it down…", Ink.Amber, "", false, null);
            Shot("4-not-landed.png", "12 words did not land · press COPY", Ink.Amber, "", false, null, unlanded: true);
            Shot("5-styling.png", "⠹ styling the text box (Claude Haiku)…", Ink.Amber, "", false, null, styling: true);
            Shot("6-no-auto-correct.png", "F1 TO TALK · WHISPER TURBO AUTO · NO AUTO CORRECT", line, "", false, null, autoCorrect: false);
            Shot("7-copied.png", "copied: Ctrl+V where you want it", Ink.Green, "", false, null, copying: true);
            Shot("8-no-key.png", "typed 12 words · Auto correct needs an Anthropic key in ⚙", Ink.Amber, "", false, null, lang: "EN");
            Shot("9-line-below.png", "F1 TO TALK · WHISPER TURBO HR · AUTO CORRECT: CLAUDE HAIKU", line, "", false, null, below: true, lang: "HR");
            return 0;
        }
    }
}
