// The blob's behaviour: F1 starts a take, F1 again sends it, Esc throws it away; the take is written down by Whisper on
// this PC, auto corrected by Claude when chosen, and typed where the cursor is. When it lands in no text box, the blob
// stays, the line says so in amber and COPY turns white.
using System;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace MantraVoiceToText
{
    public sealed class Stripe
    {
        public readonly PillWindow Window;
        PillFace F => Window.Face;
        readonly Recorder recorder = new Recorder();
        readonly DispatcherTimer tick, hideTimer;
        HotKey hotkey, escape;
        bool busy, styling, copying, unlanded;
        string lastText = "", lastLang = "auto", statusText = "";
        Color statusColour = Ink.Line;
        CancellationTokenSource cts;
        int take, spin;
        bool spinning;
        static readonly string[] braille = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        SettingsWindow settings;
        public bool NoTyping;                      // --take … --no-type: written down, not typed
        public bool FakeStyle;                     // --test-style-fake: STYLE writes the text in capitals, no Claude
        public Action TakeFinished;                // --take … --exit

        public Stripe()
        {
            var face = new PillFace(ClosePressed, LangPressed, PausePressed, CopyPressed, () => _ = StylePressed(), GearPressed, Pressed);
            Window = new PillWindow(face);
            face.LineClicked = () => { F.PlaceLine(!F.LineBelow); Prefs.Current.LineBelow = F.LineBelow; Prefs.Current.Save(); };
            face.PlaceLine(Prefs.Current.LineBelow);
            tick = new DispatcherTimer(TimeSpan.FromMilliseconds(1000.0 / 24), DispatcherPriority.Render, (s, e) => Tick(), Window.Dispatcher);
            hideTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            hideTimer.Tick += (s, e) => { hideTimer.Stop(); if (!recorder.Recording && !busy && !unlanded && !styling) Window.Hide(); };
            Window.SourceInitialized += (s, e) => BindHotkey();
            Place();
            Refresh();
            Ready();
            tick.Start();
        }

        void Place()
        {
            var p = Prefs.Current;
            var wa = SystemParameters.WorkArea;
            double x = p.X ?? wa.Left + (wa.Width - PillFace.PANEL_W) / 2, y = p.Y ?? wa.Bottom - 140;
            // a place on a screen that is gone comes back to the primary screen
            if (x < SystemParameters.VirtualScreenLeft - 100 || x > SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - 50
                || y < SystemParameters.VirtualScreenTop - 20 || y > SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - 30)
            { x = wa.Left + (wa.Width - PillFace.PANEL_W) / 2; y = wa.Bottom - 140; }
            Window.Left = x; Window.Top = y;
        }

        public void BindHotkey()
        {
            hotkey?.Dispose();
            hotkey = new HotKey(Window.Handle, Prefs.Current.Hotkey, Pressed);
            if (!hotkey.Ok) Say($"{Prefs.Current.Hotkey} is taken by another app: ⚙ to choose another", Ink.Red);
            else if (!recorder.Recording && !busy) Ready();
        }

        static string Hear => "WHISPER TURBO " + (Prefs.Current.Language == "auto" ? "AUTO" : Prefs.Current.Language.ToUpperInvariant());
        static string Engines => Hear + " · " + (Prefs.Current.AutoCorrect == "none" ? "NO AUTO CORRECT" : "AUTO CORRECT: " + Prefs.EngineTitle(Prefs.Current.AutoCorrect).ToUpperInvariant());

        public void Refresh()
        {
            F.Lang.Text = Prefs.Current.Language.ToUpperInvariant();
            F.Pause.Live = recorder.Recording;
            F.Pause.Symbol = recorder.Paused ? "" : "";
            F.Light(Prefs.Current.AutoCorrect != "none", styling, unlanded, copying);
            if (!recorder.Recording && !busy) F.Send.Symbol = "";
        }

        void Say(string text, Color colour)
        {
            statusText = text; statusColour = colour;
            F.Say(spinning ? braille[spin % braille.Length] + " " + text : text, colour);
        }

        public void Ready()
        {
            Refresh();
            if (!Ears.ModelPresent && ModelDownload.Running) { Say("the Whisper model is downloading: ⚙ → Settings shows how far", Ink.Amber); return; }
            if (!Ears.ModelPresent) { Say("no Whisper model yet: ⚙ → Settings → Download the model (547 MB)", Ink.Amber); return; }
            if (Ears.VcRuntimeMissing) { Say(Ears.VcRuntimeSay, Ink.Amber); return; }
            Say($"{Prefs.Current.Hotkey.ToUpperInvariant()} TO TALK · " + Engines, Ink.Line);
        }

        void Tick()
        {
            if (recorder.Recording)
            {
                F.Wave.Moving = !recorder.Paused;
                F.Wave.Take(recorder.Meter());
                int s = (int)recorder.Seconds;
                Say((recorder.Paused ? "PAUSED " : "● ") + $"{s / 60}:{s % 60:00} · " + Engines, recorder.Paused ? Ink.Line : Ink.Red);
            }
            else if (F.Wave.Moving || spinning) { F.Wave.Moving = false; F.Wave.Take(null); }
            if (spinning && (++spin % 2 == 0)) F.Say(braille[(spin / 2) % braille.Length] + " " + statusText, statusColour);
        }

        public void Show()
        {
            hideTimer.Stop();
            Window.ShowQuietly();
        }

        void HideSoon(double secs = 3)
        {
            hideTimer.Stop();
            if (!Prefs.Current.AfterHide || unlanded) return;
            hideTimer.Interval = TimeSpan.FromSeconds(secs);
            hideTimer.Start();
        }

        // ---------- the take ----------

        public void Pressed()
        {
            if (busy) { Show(); Say("still writing the last take down…", Ink.Amber); return; }
            if (recorder.Recording) Finish();
            else Listen();
        }

        void Listen()
        {
            Show();
            if (!Ears.ModelPresent) { Say("no Whisper model yet: ⚙ → Settings → Download the model (547 MB)", Ink.Amber); return; }
            unlanded = false;
            if (!recorder.Start(Prefs.Current.Microphone)) { Say("the microphone did not start: " + recorder.Error, Ink.Red); return; }
            _ = Ears.Warm().ContinueWith(t => { }, TaskScheduler.Default);   // the model loads while the speaker talks
            escape?.Dispose();
            escape = new HotKey(Window.Handle, "Escape", Cancel);
            F.Send.Symbol = "";                      // arrow up: send
            Refresh();
            Log.Write("take: recording");
        }

        void Finish()
        {
            double secs = recorder.Seconds;
            double loudest = Recorder.Db(recorder.Peak);
            var samples = recorder.Stop();
            escape?.Dispose(); escape = null;
            Refresh();
            if (Gate(secs, loudest)) return;
            _ = Process(samples, secs);
        }

        /// The silence gate: Whisper invents words for silence, so a take under 0.5 s or quieter than -45 dBFS is not sent.
        bool Gate(double secs, double loudest)
        {
            if (secs >= 0.5 && loudest >= -45) return false;
            Say($"nothing said ({secs:0.0} s, {loudest:0} dB): not sent", Ink.Line);
            Log.Write($"dropped: {secs:0.0} s, loudest {loudest:0} dB");
            HideSoon();
            TakeFinished?.Invoke();
            return true;
        }

        /// --take <file.wav>: a recording through the same road as a take from the microphone.
        public async Task TakeFile(string path)
        {
            Show();
            float[] s;
            try { s = WavFile.Read16kMono(path); }
            catch (Exception e) { Say("the file could not be read: " + e.Message, Ink.Red); Log.Write("--take: " + e); TakeFinished?.Invoke(); return; }
            double secs = s.Length / (double)Recorder.Rate;
            double loudest = Recorder.Db(s.Length == 0 ? 0 : s.Max(Math.Abs));
            Log.Write($"--take {path}: {secs:0.0} s, peak {loudest:0.0} dBFS");
            if (Gate(secs, loudest)) return;
            await Process(s, secs);
        }

        async Task Process(float[] samples, double secs)
        {
            busy = true; take++; int mine = take;
            cts?.Cancel(); cts = new CancellationTokenSource(); var ct = cts.Token;
            escape?.Dispose(); escape = new HotKey(Window.Handle, "Escape", Cancel);
            F.Send.Symbol = "";                      // … while it works
            spinning = true;
            Say("writing it down…", Ink.Amber);
            var lang0 = Prefs.Current.Language;
            var family = Prefs.Current.AutoCorrect;
            var t0 = Stopwatch.StartNew();
            Ears.Heard heard;
            try { heard = await Task.Run(() => Ears.Hear(samples, lang0, ct), ct); }
            catch (OperationCanceledException) { return; }
            catch (Exception e) { heard = new Ears.Heard { Error = "Whisper: " + e.Message }; Log.Write("whisper: " + e); }
            double tHear = t0.Elapsed.TotalSeconds;
            if (mine != take || ct.IsCancellationRequested) return;
            if (heard.Error != null || string.IsNullOrWhiteSpace(heard.Text))
            {
                Done();
                Say(heard.Error ?? "nothing heard", heard.Error?.StartsWith("nothing said") == true ? Ink.Line : Ink.Red);
                Log.Write($"failed after {tHear:0.0} s: {heard.Error ?? "nothing heard"}");
                HideSoon(5);
                TakeFinished?.Invoke();
                return;
            }
            var words = heard.Text;
            var lang = lang0 == "auto" ? (heard.Language == "en" || heard.Language == "hr" ? heard.Language : "auto") : lang0;
            string final = words, warning = null;
            var t1 = Stopwatch.StartNew();
            if (family != "none")
            {
                if (!ApiKey.Has) warning = Claude.NoKey;
                else
                {
                    Say($"auto correct ({Prefs.EngineTitle(family)})…", Ink.Amber);
                    try { final = await Claude.Clean(words, lang, family, ct); }
                    catch (OperationCanceledException) { return; }
                    catch (Exception e) { warning = "not auto corrected: " + Claude.Why(e); Log.Write("auto correct: " + Claude.Why(e)); }
                }
            }
            double tStyle = t1.Elapsed.TotalSeconds;
            if (mine != take || ct.IsCancellationRequested) return;
            Done();
            lastText = final; lastLang = lang;
            History.Add(new Take { At = DateTime.Now, Heard = words, Text = final, Language = heard.Language ?? lang, Correction = family == "none" ? "none" : warning == null ? Prefs.EngineTitle(family) : "failed: " + warning, Seconds = secs });
            settings?.ReloadHistory();
            int n = final.Split(new[] { ' ', '\n' }, StringSplitOptions.RemoveEmptyEntries).Length;
            Log.Write($"heard ({heard.Language}, {secs:0.0} s of audio, {tHear:0.0} s): {words}");
            if (family != "none") Log.Write($"  auto correct ({family}, {tStyle:0.0} s): {(warning ?? final)}");
            if (NoTyping)
            {
                Say($"test: {n} words, not typed · {tHear:0.0} + {tStyle:0.0} s" + (warning != null ? " · " + warning : ""), warning != null ? Ink.Amber : Ink.Green);
                TakeFinished?.Invoke();
                return;
            }
            var landing = await Hands.Insert(final);
            if (landing == Landing.Nowhere) { NotLanded($"{n} words did not land"); Log.Write("landing: nowhere"); TakeFinished?.Invoke(); return; }
            if (warning != null) Say($"typed {n} words · {warning}", Ink.Amber);
            else Say($"typed {n} words · {tHear:0.0} + {tStyle:0.0} s", Ink.Green);
            Log.Write($"landing: typed, {n} words");
            HideSoon();
            TakeFinished?.Invoke();
        }

        void Done()
        {
            busy = false; spinning = false;
            escape?.Dispose(); escape = null;
            Refresh();
        }

        void NotLanded(string text)
        {
            unlanded = true; hideTimer.Stop();
            Refresh();
            Say(text + " · press COPY", Ink.Amber);
        }

        public void Cancel()
        {
            if (recorder.Recording)
            {
                recorder.Stop();
                escape?.Dispose(); escape = null;
                Refresh();
                Say("thrown away", Ink.Line);
                Log.Write("take thrown away");
                HideSoon();
                return;
            }
            if (busy)
            {
                take++; cts?.Cancel();
                Done();
                Say("cancelled", Ink.Line);
                Log.Write("take cancelled while it was written down");
                HideSoon();
            }
        }

        void ClosePressed()
        {
            if (recorder.Recording || busy) { Cancel(); return; }
            unlanded = false; styling = false; Refresh();
            hideTimer.Stop();
            Window.Hide();
        }

        void LangPressed()
        {
            var p = Prefs.Current;
            p.Language = p.Language == "auto" ? "en" : p.Language == "en" ? "hr" : "auto";
            p.Save();
            Refresh();
            if (!recorder.Recording && !busy) Ready();
        }

        void PausePressed()
        {
            if (!recorder.Recording) return;
            recorder.Paused = !recorder.Paused;
            Refresh();
        }

        void CopyPressed()
        {
            if (lastText.Length == 0) { Say("nothing to copy yet: dictate first", Ink.Amber); return; }
            Hands.SetClipboard(lastText);
            unlanded = false; copying = true; Refresh();
            Say("copied: Ctrl+V where you want it", Ink.Green);
            var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            t.Tick += (s, e) =>
            {
                t.Stop(); copying = false; Refresh();
                string now = null; try { now = Clipboard.GetText(); } catch { }
                Log.Write($"COPY: {lastText.Length} characters on the clipboard; read back a second later: {(now == lastText ? "the same" : "different (" + (now?.Length ?? -1) + ")")}");
            };
            t.Start();
            HideSoon();
        }

        async Task StylePressed()
        {
            if (recorder.Recording) { Say("STYLE works on text already written: send this take first", Ink.Amber); return; }
            if (busy) { Say("still writing the last take down: STYLE after it", Ink.Amber); return; }
            if (styling) return;
            if (!FakeStyle && !ApiKey.Has) { Say("STYLE needs an Anthropic key in ⚙", Ink.Amber); return; }
            hideTimer.Stop();
            var (box, why) = await Task.Run(Hands.ReadFocused);
            if (box == null) { Say(why, Ink.Amber); return; }
            if (box.Text.Trim().Length == 0) { Say("this text box is empty: write or select something, then STYLE", Ink.Amber); return; }
            if (box.Text.Length > 20000) { Say($"too much text for STYLE ({box.Text.Length} characters): select a part, then STYLE", Ink.Amber); return; }
            var family = Prefs.Current.StyleEngine;
            styling = true; spinning = true; Refresh();
            Say($"styling {box.What} ({(FakeStyle ? "test: capitals" : Prefs.EngineTitle(family))})…", Ink.Amber);
            string styled;
            try
            {
                styled = FakeStyle ? box.Text.ToUpperInvariant()
                                   : await Claude.Clean(box.Text, Prefs.Current.Language, family, CancellationToken.None);
            }
            catch (Exception e)
            {
                styling = false; spinning = false; Refresh();
                Say("not styled: " + Claude.Why(e), Ink.Red);
                return;
            }
            styling = false; spinning = false; Refresh();
            int n = styled.Split(new[] { ' ', '\n' }, StringSplitOptions.RemoveEmptyEntries).Length;
            if (styled == box.Text) { Say("nothing to correct · ✕ closes", Ink.Green); return; }
            var how = await Hands.WriteBack(box, styled);
            lastText = styled;
            Log.Write($"STYLE: {box.What}, {n} words, {how}");
            if (how == "clipboard") Say("styled: on the clipboard, press Ctrl+V", Ink.Amber);
            else Say($"styled: {box.What}, {n} words ({how}) · ✕ closes", Ink.Green);
        }

        // ---------- ⚙ ----------

        void GearPressed()
        {
            var m = new ContextMenu { Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom, PlacementTarget = F.Gear };
            void Head(string t) => m.Items.Add(new MenuItem { Header = t, IsEnabled = false, FontWeight = FontWeights.SemiBold });
            MenuItem Item(string t, bool check, Action a) { var i = new MenuItem { Header = t, IsCheckable = false, IsChecked = check }; i.Click += (s, e) => a(); m.Items.Add(i); return i; }
            var p = Prefs.Current;
            Head("Language");
            foreach (var l in new[] { "auto", "en", "hr" })
                Item(Prefs.LanguageTitle(l), p.Language == l, () => { p.Language = l; p.Save(); Refresh(); Ready(); });
            m.Items.Add(new Separator());
            Head("Auto correct (after a take)");
            foreach (var (k, t) in new[] { ("none", "None"), ("haiku", "Claude Haiku (default, fastest)"), ("sonnet", "Claude Sonnet"), ("opus", "Claude Opus (best)") })
                Item(t, p.AutoCorrect == k, () => { p.AutoCorrect = k; p.Save(); Refresh(); Ready(); });
            m.Items.Add(new Separator());
            Head("The STYLE button");
            foreach (var (k, t) in new[] { ("haiku", "Claude Haiku"), ("sonnet", "Claude Sonnet"), ("opus", "Claude Opus") })
                Item(t, p.StyleEngine == k, () => { p.StyleEngine = k; p.Save(); });
            m.Items.Add(new Separator());
            var hist = new MenuItem { Header = "History" };
            if (History.Items.Count == 0) hist.Items.Add(new MenuItem { Header = "no takes yet", IsEnabled = false });
            foreach (var t in History.Items.Take(15))
            {
                var label = t.At.ToString("d.M. HH:mm") + "   " + (t.Text.Length > 60 ? t.Text.Substring(0, 60) + "…" : t.Text);
                var i = new MenuItem { Header = label, ToolTip = "Click to copy:\n" + t.Text };
                var text = t.Text;
                i.Click += (s, e) => { Hands.SetClipboard(text); Say("copied from the history: Ctrl+V where you want it", Ink.Green); };
                hist.Items.Add(i);
            }
            if (History.Items.Count > 0)
            {
                hist.Items.Add(new Separator());
                var all = new MenuItem { Header = "Open the whole history…" };
                all.Click += (s, e) => OpenSettings(history: true);
                hist.Items.Add(all);
            }
            m.Items.Add(hist);
            var again = new MenuItem { Header = "Type the last text again", IsEnabled = lastText.Length > 0 };
            again.Click += async (s, e) =>
            {
                await Task.Delay(250);                          // the menu closes and the focus is back in the app
                var l = await Hands.Insert(lastText);
                if (l == Landing.Nowhere) NotLanded("did not land"); else Say("typed again", Ink.Green);
            };
            m.Items.Add(again);
            m.Items.Add(new Separator());
            Item("Settings…", false, () => OpenSettings());
            Item("Quit " + Paths.Name, false, Quit);
            m.IsOpen = true;
        }

        public void OpenSettings(bool history = false)
        {
            if (settings == null || !settings.IsLoaded)
            {
                settings = new SettingsWindow(this);
                settings.Closed += (s, e) => settings = null;
            }
            settings.Show();
            if (history) settings.ShowHistory();
            settings.Activate();
        }

        public void SettingsChanged() { Refresh(); if (!recorder.Recording && !busy) Ready(); }

        public void Quit()
        {
            try { recorder.Stop(); } catch { }
            hotkey?.Dispose(); escape?.Dispose();
            Log.Write("quit");
            Application.Current.Shutdown();
        }
    }
}
