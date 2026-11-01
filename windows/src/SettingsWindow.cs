// ⚙ → Settings: ON · OFF · name · TOP · ✕ on the first row (OFF quits, TOP keeps this window on top), then the
// microphone, the hotkey, the language, Auto correct and its additions, the STYLE engine, the Anthropic key (stored with
// DPAPI, never shown again), the Whisper model (download with a progress bar), After hide, and the history.
using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace MantraVoiceToText
{
    public sealed class SettingsWindow : Window
    {
        readonly Stripe stripe;
        readonly StackPanel body = new StackPanel { Margin = new Thickness(18, 10, 18, 18) };
        readonly ListBox history = new ListBox { Height = 220 };
        TextBlock keyState, modelState;
        ProgressBar modelBar;
        Button download;
        TextBox hotkeyBox;
        static readonly Brush ground = new SolidColorBrush(Color.FromRgb(0x1E, 0x1E, 0x21)), card = new SolidColorBrush(Color.FromRgb(0x2A, 0x2A, 0x2E)),
            text = new SolidColorBrush(Color.FromRgb(0xE6, 0xE6, 0xE6)), dim = new SolidColorBrush(Color.FromRgb(0x9A, 0x9A, 0x9A));
        Expander historyBox;

        public SettingsWindow(Stripe stripe)
        {
            this.stripe = stripe;
            Title = Paths.Name + " · Settings";
            Width = 560; Height = 760; MinWidth = 420; MinHeight = 400;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = ground; Foreground = text;
            Topmost = Prefs.Current.SettingsOnTop;
            FontFamily = new FontFamily("Segoe UI"); FontSize = 13;
            var outer = new DockPanel();
            outer.Children.Add(TopRow()); DockPanel.SetDock(outer.Children[0], Dock.Top);
            outer.Children.Add(new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
            Content = outer;
            Build();
        }

        Button Btn(string t, Action a, Brush bg = null, Brush fg = null)
        {
            var b = new Button { Content = t, Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(0, 0, 6, 0), Background = bg ?? card, Foreground = fg ?? text, BorderBrush = Brushes.Transparent, Cursor = Cursors.Hand };
            b.Click += (s, e) => a();
            return b;
        }

        UIElement TopRow()
        {
            var row = new DockPanel { Margin = new Thickness(12, 10, 12, 4), LastChildFill = true };
            var left = new StackPanel { Orientation = Orientation.Horizontal };
            left.Children.Add(Btn("ON", () => { }, Ink.B(Ink.Green), Brushes.Black));
            left.Children.Add(Btn("OFF", stripe.Quit));
            var right = new StackPanel { Orientation = Orientation.Horizontal };
            Button top = null;
            top = Btn("TOP", () =>
            {
                Prefs.Current.SettingsOnTop = !Prefs.Current.SettingsOnTop; Prefs.Current.Save();
                Topmost = Prefs.Current.SettingsOnTop;
                top.Background = Topmost ? Ink.B(Ink.Blue) : card;
            }, Prefs.Current.SettingsOnTop ? Ink.B(Ink.Blue) : card);
            top.ToolTip = "Keep this window on top";
            right.Children.Add(top);
            var x = Btn("✕", Close); x.Margin = new Thickness(0); x.ToolTip = "Close this window (the app stays on)";
            right.Children.Add(x);
            DockPanel.SetDock(left, Dock.Left); DockPanel.SetDock(right, Dock.Right);
            row.Children.Add(left); row.Children.Add(right);
            row.Children.Add(new TextBlock { Text = $"{Paths.Name}   v{Paths.Version}", FontWeight = FontWeights.SemiBold, FontSize = 15, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center });
            return row;
        }

        void Head(string t, string note = null)
        {
            body.Children.Add(new TextBlock { Text = t, FontWeight = FontWeights.SemiBold, FontSize = 14, Margin = new Thickness(0, 14, 0, 4) });
            if (note != null) body.Children.Add(new TextBlock { Text = note, Foreground = dim, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 4) });
        }

        ComboBox Combo((string key, string title)[] items, string current, Action<string> picked)
        {
            var c = new ComboBox { MinWidth = 260, HorizontalAlignment = HorizontalAlignment.Left };
            foreach (var (k, t) in items) c.Items.Add(new ComboBoxItem { Content = t, Tag = k });
            c.SelectedIndex = Math.Max(0, Array.FindIndex(items, i => i.key == current));
            c.SelectionChanged += (s, e) => { if (c.SelectedItem is ComboBoxItem i) picked((string)i.Tag); };
            body.Children.Add(c);
            return c;
        }

        void Build()
        {
            var p = Prefs.Current;

            Head("Microphone");
            var mics = new[] { ("", "The Windows default microphone") }.Concat(Recorder.Devices().Select(d => (d, d))).ToArray();
            Combo(mics, p.Microphone, k => { p.Microphone = k; p.Save(); });

            Head("Hotkey", "Starts a take; pressed again it sends it. Esc while recording throws the take away. Click the box and press the key (with Ctrl, Alt, Shift or Win if you like).");
            hotkeyBox = new TextBox { Text = p.Hotkey, Width = 200, HorizontalAlignment = HorizontalAlignment.Left, IsReadOnly = true, Background = card, Foreground = text, Padding = new Thickness(4) };
            hotkeyBox.PreviewKeyDown += (s, e) =>
            {
                e.Handled = true;
                var k = e.Key == Key.System ? e.SystemKey : e.Key;
                if (k is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) return;
                var mods = "";
                if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) mods += "Ctrl+";
                if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) mods += "Alt+";
                if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) mods += "Shift+";
                if (Keyboard.Modifiers.HasFlag(ModifierKeys.Windows)) mods += "Win+";
                if (k == Key.Escape && mods == "") return;
                var chord = mods + k;
                hotkeyBox.Text = chord;
                p.Hotkey = chord; p.Save();
                stripe.BindHotkey();
            };
            body.Children.Add(hotkeyBox);

            Head("Language", "Whisper Auto finds the language of each take by itself.");
            Combo(new[] { ("auto", "Auto"), ("en", "English"), ("hr", "Croatian") }, p.Language, k => { p.Language = k; p.Save(); stripe.SettingsChanged(); });

            Head("Auto correct (after a take)", "Claude cleans what was said before it is typed: an edit, not a summary. Paid per message on your own Anthropic key.");
            Combo(new[] { ("none", "None"), ("haiku", "Claude Haiku (default, fastest)"), ("sonnet", "Claude Sonnet"), ("opus", "Claude Opus (best)") },
                  p.AutoCorrect, k => { p.AutoCorrect = k; p.Save(); stripe.SettingsChanged(); });
            body.Children.Add(new TextBlock { Text = "Your own additions to the rules (Auto correct and STYLE):", Margin = new Thickness(0, 8, 0, 2), Foreground = dim });
            var extra = new TextBox { Text = p.Extra, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Height = 70, Background = card, Foreground = text, Padding = new Thickness(4), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            extra.LostFocus += (s, e) => { p.Extra = extra.Text; p.Save(); };
            body.Children.Add(extra);

            Head("The STYLE button", "Click into any text box, then STYLE on the blob: the selection (or the whole box) is restyled in place.");
            Combo(new[] { ("haiku", "Claude Haiku"), ("sonnet", "Claude Sonnet"), ("opus", "Claude Opus") }, p.StyleEngine, k => { p.StyleEngine = k; p.Save(); });

            Head("Anthropic key", "Kept on this PC for this Windows user only (DPAPI) and never shown again. The model is the newest Haiku, Sonnet or Opus your key lists.");
            var keyRow = new StackPanel { Orientation = Orientation.Horizontal };
            var keyBox = new PasswordBox { Width = 250, Background = card, Foreground = text, Padding = new Thickness(4), Margin = new Thickness(0, 0, 6, 0) };
            keyRow.Children.Add(keyBox);
            keyRow.Children.Add(Btn("Save", () =>
            {
                if (keyBox.Password.Trim().Length == 0) { keyState.Text = "type or paste the key first"; return; }
                ApiKey.Set(keyBox.Password); keyBox.Clear();
                Prefs.Current.ModelIds.Clear(); Prefs.Current.ModelIdsAt.Clear(); Prefs.Current.Save();
                ShowKey("saved");
            }));
            keyRow.Children.Add(Btn("Test", async () =>
            {
                var k = keyBox.Password.Trim().Length > 0 ? keyBox.Password.Trim() : ApiKey.Get();
                if (k == null) { keyState.Text = "no key to test"; return; }
                keyState.Text = "asking Anthropic…";
                try { keyState.Text = await Claude.Test(k); }
                catch (Exception e) { keyState.Text = "the key did not work: " + Claude.Why(e); }
            }));
            keyRow.Children.Add(Btn("Forget", () => { ApiKey.Forget(); ShowKey("forgotten"); }));
            body.Children.Add(keyRow);
            keyState = new TextBlock { Foreground = dim, Margin = new Thickness(0, 4, 0, 0), TextWrapping = TextWrapping.Wrap };
            body.Children.Add(keyState);
            ShowKey(null);

            Head("Whisper model", "large-v3-turbo (q5_0), 547 MB, runs on this PC, offline. The download always resumes where it stopped.");
            modelState = new TextBlock { Foreground = dim, TextWrapping = TextWrapping.Wrap };
            body.Children.Add(modelState);
            modelBar = new ProgressBar { Height = 10, Maximum = 1, Margin = new Thickness(0, 6, 0, 6), Visibility = Visibility.Collapsed };
            body.Children.Add(modelBar);
            var mrow = new StackPanel { Orientation = Orientation.Horizontal };
            download = Btn("Download the model (547 MB)", Download);
            mrow.Children.Add(download);
            mrow.Children.Add(Btn("Open the folder", () => System.Diagnostics.Process.Start("explorer.exe", Paths.Models)));
            body.Children.Add(mrow);
            if (Ears.VcRuntimeMissing)
            {
                body.Children.Add(new TextBlock { Text = "Whisper needs the Microsoft Visual C++ runtime (2015-2022), which this PC does not have yet. Get it from Microsoft, install it, then start this app again.", Foreground = Ink.B(Ink.Amber), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 4) });
                body.Children.Add(Btn("Get it (Microsoft, " + Ears.VcRuntimeUrl.Substring(Ears.VcRuntimeUrl.LastIndexOf('/') + 1) + ")", () => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Ears.VcRuntimeUrl) { UseShellExecute = true })));
            }
            ShowModel();
            ModelDownload.Changed += ModelChanged;
            Closed += (s, e) => ModelDownload.Changed -= ModelChanged;

            Head("After hide");
            var hide = new CheckBox { Content = "Hide the blob 3 s after each take (F1 brings it back)", IsChecked = p.AfterHide, Foreground = text };
            hide.Click += (s, e) => { p.AfterHide = hide.IsChecked == true; p.Save(); };
            body.Children.Add(hide);

            historyBox = new Expander { Header = "History (newest first; double-click a take to copy it)", Margin = new Thickness(0, 16, 0, 0), Foreground = text };
            var hp = new StackPanel();
            history.Background = card; history.Foreground = text;
            history.MouseDoubleClick += (s, e) => { if (history.SelectedItem is ListBoxItem i) { Hands.SetClipboard((string)i.Tag); Title = Paths.Name + " · copied"; } };
            hp.Children.Add(history);
            var hrow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
            hrow.Children.Add(Btn("Copy", () => { if (history.SelectedItem is ListBoxItem i) Hands.SetClipboard((string)i.Tag); }));
            hrow.Children.Add(Btn("Clean the history", () =>
            {
                if (MessageBox.Show(this, "Delete every take in the history?", Paths.Name, MessageBoxButton.YesNo) == MessageBoxResult.Yes) { History.Clear(); ReloadHistory(); }
            }));
            hrow.Children.Add(Btn("Open the log", () => System.Diagnostics.Process.Start("notepad.exe", Paths.LogFile)));
            hp.Children.Add(hrow);
            historyBox.Content = hp;
            body.Children.Add(historyBox);
            ReloadHistory();
        }

        void ShowKey(string what)
        {
            keyState.Text = (ApiKey.Has ? "a key is stored" : "no key: Auto correct and STYLE need one (console.anthropic.com)") + (what != null ? " · " + what : "");
            stripe.SettingsChanged();
        }

        void ShowModel()
        {
            if (Ears.ModelPresent)
            {
                modelState.Text = $"ready: {Paths.Model} ({new FileInfo(Paths.Model).Length / 1048576} MB)";
                download.IsEnabled = false; download.Content = "The model is here"; modelBar.Visibility = Visibility.Collapsed;
                stripe.SettingsChanged();
                return;
            }
            long part = File.Exists(ModelDownload.Part) ? new FileInfo(ModelDownload.Part).Length : 0;
            if (ModelDownload.Running)
            {
                modelBar.Visibility = Visibility.Visible;
                modelBar.Value = Math.Max(ModelDownload.Have, part) / (double)ModelDownload.Total;
                modelState.Text = ModelDownload.State + " · it goes on by itself, also after the app is closed and opened again";
                download.IsEnabled = false; download.Content = "Downloading…";
            }
            else
            {
                modelBar.Visibility = part > 0 ? Visibility.Visible : Visibility.Collapsed;
                modelBar.Value = part / (double)ModelDownload.Total;
                modelState.Text = part > 0 ? $"{part / 1048576} of {ModelDownload.Total / 1048576} MB here: press to go on from there" : "not downloaded yet: " + Paths.Model;
                download.IsEnabled = true; download.Content = part > 0 ? "Go on with the download" : "Download the model (547 MB)";
            }
        }

        public void ShowHistory() { historyBox.IsExpanded = true; historyBox.BringIntoView(); }

        public void ReloadHistory()
        {
            history.Items.Clear();
            foreach (var t in History.Items)
                history.Items.Add(new ListBoxItem { Content = t.At.ToString("d.M.yyyy HH:mm") + "  " + t.Text, Tag = t.Text, ToolTip = "heard: " + t.Heard + "\nauto correct: " + t.Correction });
        }

        void Download()
        {
            ModelDownload.Start();
            ShowModel();
        }

        void ModelChanged() => Dispatcher.BeginInvoke(new Action(ShowModel));

    }
}
