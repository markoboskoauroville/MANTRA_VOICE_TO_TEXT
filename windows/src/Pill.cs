// THE BLOB: a dark rounded pill 430 x 40 in a 460 x 60 window, with a small status line above it (or below: a short
// click on the line flips it). ✕ [AUTO] the voice in eleven bars ⏸ COPY STYLE ⚙ and the blue round button (mic → start,
// arrow-up → send). The window is topmost, has no shadow and never takes the keyboard focus (WS_EX_NOACTIVATE +
// WS_EX_TOOLWINDOW, and WM_MOUSEACTIVATE answered MA_NOACTIVATE), so the words always go to the app the speaker was in.
// Any part that is not a button drags it.
using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace MantraVoiceToText
{
    public static class Ink
    {
        static Color C(uint rgb) => Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
        public static readonly Color Dim = C(0x6B6B6B), Lit = C(0xF2F2F2), Green = C(0x4DD173), Blue = C(0x3D7BF7),
            Grey = C(0x5C5C5C), Amber = C(0xFAB833), Red = C(0xF25450), Line = Color.FromArgb(0xBF, 0xFF, 0xFF, 0xFF);
        public static SolidColorBrush B(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
    }

    /// One button of the pill: a symbol (Segoe Fluent Icons / MDL2) or a word, optionally on a filled circle.
    public sealed class BlobButton : FrameworkElement
    {
        static readonly FontFamily icons = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets");
        static readonly Typeface word = new Typeface(new FontFamily("Consolas"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
        static readonly Typeface glyph = new Typeface(icons, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        string symbol, text; Color tint; Color? circle; bool live = true, bracketed;
        public Action Pressed;
        public string Id;
        public string Symbol { get => symbol; set { if (symbol != value) { symbol = value; InvalidateVisual(); } } }
        public string Text { get => text; set { if (text != value) { text = value; InvalidateVisual(); } } }
        public Color Tint { get => tint; set { if (tint != value) { tint = value; InvalidateVisual(); } } }
        public Color? Circle { get => circle; set { if (circle != value) { circle = value; InvalidateVisual(); } } }
        public bool Live { get => live; set { if (live != value) { live = value; InvalidateVisual(); } } }
        public bool Bracketed { get => bracketed; set { if (bracketed != value) { bracketed = value; InvalidateVisual(); } } }

        public BlobButton(string id, string symbol, double w, double h, Color? circle, Color tint, string tip, Action pressed)
        {
            Id = id; this.symbol = symbol; Width = w; Height = h; this.circle = circle; this.tint = tint; Pressed = pressed;
            ToolTip = tip; Cursor = Cursors.Hand;
            System.Windows.Automation.AutomationProperties.SetName(this, tip);
            System.Windows.Automation.AutomationProperties.SetAutomationId(this, id);
        }

        // every button of the blob is a UI Automation button that can be invoked (screen readers, tests)
        protected override System.Windows.Automation.Peers.AutomationPeer OnCreateAutomationPeer() => new Peer(this);
        sealed class Peer : System.Windows.Automation.Peers.FrameworkElementAutomationPeer, System.Windows.Automation.Provider.IInvokeProvider
        {
            readonly BlobButton b;
            public Peer(BlobButton b) : base(b) { this.b = b; }
            protected override System.Windows.Automation.Peers.AutomationControlType GetAutomationControlTypeCore() => System.Windows.Automation.Peers.AutomationControlType.Button;
            protected override string GetClassNameCore() => "BlobButton";
            protected override string GetNameCore() => b.text ?? (b.ToolTip as string) ?? b.Id;
            protected override bool IsEnabledCore() => b.live;
            public override object GetPattern(System.Windows.Automation.Peers.PatternInterface p) => p == System.Windows.Automation.Peers.PatternInterface.Invoke ? this : base.GetPattern(p);
            public void Invoke() { if (b.live) b.Dispatcher.BeginInvoke(new Action(() => b.Pressed?.Invoke())); }
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e) { e.Handled = true; CaptureMouse(); }
        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
        {
            e.Handled = true;
            ReleaseMouseCapture();
            var p = e.GetPosition(this);
            if (live && p.X >= 0 && p.Y >= 0 && p.X <= ActualWidth && p.Y <= ActualHeight) Pressed?.Invoke();
        }

        protected override void OnRender(DrawingContext dc)
        {
            double w = ActualWidth, h = ActualHeight, d = Math.Min(w, h) - 6;
            var c = new Point(w / 2, h / 2);
            dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, w, h));          // the whole place takes the click
            if (circle.HasValue) dc.DrawEllipse(Ink.B(circle.Value), null, c, d / 2, d / 2);
            var col = Ink.B(live ? tint : Ink.Dim);
            var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
            FormattedText ft = text != null
                ? new FormattedText(bracketed ? "[" + text + "]" : text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, word, 11, col, dpi)
                : new FormattedText(symbol ?? "", CultureInfo.InvariantCulture, FlowDirection.LeftToRight, glyph, circle.HasValue ? 13 : 15, col, dpi);
            dc.DrawText(ft, new Point(c.X - ft.Width / 2, c.Y - ft.Height / 2));
        }
    }

    /// The voice: eleven short white bars, round-ended, each one band; dots while silent. Ballistics of the Mac meter:
    /// a 4.5 dB/oct tilt about 1 kHz, attack at once, release 120 dB/s, top -18 dB, range 50 dB.
    public sealed class WaveView : FrameworkElement
    {
        const double TILT = 4.5, RELEASE = 120, TOP = -18, RANGE = 50;
        public bool Moving;
        public Color Color = Color.FromArgb(0xEB, 0xFF, 0xFF, 0xFF);
        readonly double[] spec = Enumerable.Repeat(-140.0, 11).ToArray();
        DateTime last = DateTime.Now;

        public void Take(double[] db)
        {
            var t = DateTime.Now; double dt = Math.Min(0.2, (t - last).TotalSeconds); last = t;
            for (int c = 0; c < 11; c++)
            {
                double m = Moving && db != null && c < db.Length ? db[c] : -140;
                if (m > -140) m += TILT * Math.Log2(Bands.Centres[c] / 1000);
                spec[c] = m > spec[c] ? m : Math.Max(m, spec[c] - RELEASE * dt);
            }
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext dc)
        {
            double gap = 4, w = 2.6, H = ActualHeight;
            double x0 = (ActualWidth - 11 * w - 10 * gap) / 2;
            var b = Ink.B(Color);
            for (int i = 0; i < 11; i++)
            {
                double frac = Math.Min(1, Math.Max(0, (spec[i] - (TOP - RANGE)) / RANGE));
                double h = Math.Max(w, frac * (H - 16) + w);
                var r = new Rect(x0 + i * (w + gap), H - 9 - h, w, h);
                dc.DrawRoundedRectangle(b, null, r, w / 2, w / 2);
            }
        }
    }

    /// The face of the blob: the line and the pill. Used by the window and by --pill-shot.
    public sealed class PillFace : Canvas
    {
        public const double PANEL_W = 460, PILL_W = 430, PILL_H = 40, LINE_H = 20;
        public readonly Border Pill, Band;
        public readonly TextBlock Line;
        public readonly WaveView Wave;
        public readonly BlobButton Close, Lang, Pause, Copy, StyleBtn, Gear, Send;
        public bool LineBelow { get; private set; }
        public Action LineClicked;

        public PillFace(Action close, Action lang, Action pause, Action copy, Action style, Action gear, Action send)
        {
            Width = PANEL_W; Height = PILL_H + LINE_H;
            Background = new SolidColorBrush(Color.FromArgb(3, 0, 0, 0));       // 1 %: the empty parts drag too, the eye sees nothing
            Pill = new Border
            {
                Width = PILL_W, Height = PILL_H, CornerRadius = new CornerRadius(PILL_H / 2),
                Background = new SolidColorBrush(Color.FromArgb(0xF7, 0x1C, 0x1C, 0x1F)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF)), BorderThickness = new Thickness(1),
            };
            var inner = new Canvas { Width = PILL_W, Height = PILL_H };
            Pill.Child = inner;
            Color white = Ink.Lit;
            Close = new BlobButton("close", "", 36, 36, Ink.Grey, white, "Throw this take away (Esc), or hide the blob", close);
            Lang = new BlobButton("language", null, 52, 36, null, white, "The language: Auto, English or Croatian", lang) { Text = "AUTO", Bracketed = true };
            Wave = new WaveView { Width = 80, Height = PILL_H, IsHitTestVisible = false };
            Pause = new BlobButton("pause", "", 40, 36, null, white, "Pause; press again to go on", pause);
            Copy = new BlobButton("copy", null, 56, 36, null, Ink.Dim, "Copy the last words to the clipboard, then Ctrl+V where you want them", copy) { Text = "COPY" };
            StyleBtn = new BlobButton("style", null, 60, 36, null, Ink.Dim, "Style: the text box you clicked into (its selection, or all of it) is corrected in place", style) { Text = "STYLE" };
            Gear = new BlobButton("settings", "", 36, 36, null, white, "Language, Auto correct, STYLE engine, history, settings", gear);
            Send = new BlobButton("send", "", 36, 36, Ink.Blue, white, "Start a take (F1); while recording: send it", send);
            void At(UIElement e, double x, double y = 2) { SetLeft(e, x - 1); SetTop(e, y - 1); inner.Children.Add(e); }
            At(Close, 4); At(Lang, 42); At(Wave, 96, 0); At(Pause, 180); At(Copy, 222); At(StyleBtn, 282); At(Gear, 348); At(Send, 390);

            Line = new TextBlock
            {
                FontFamily = new FontFamily("Consolas"), FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Ink.B(Ink.Line),
                TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(8, 1, 8, 1), VerticalAlignment = VerticalAlignment.Center,
            };
            Band = new Border
            {
                Child = Line, CornerRadius = new CornerRadius(6), Background = new SolidColorBrush(Color.FromArgb(0x8C, 0, 0, 0)),
                Height = LINE_H - 2, MaxWidth = PANEL_W, HorizontalAlignment = HorizontalAlignment.Center,
            };
            var lineHolder = new Grid { Width = PANEL_W, Height = LINE_H - 2 };
            lineHolder.Children.Add(Band);
            LineHolder = lineHolder;
            Children.Add(Pill); Children.Add(lineHolder);
            PlaceLine(false);
        }

        public readonly Grid LineHolder;

        public void PlaceLine(bool below)
        {
            LineBelow = below;
            SetLeft(Pill, (PANEL_W - PILL_W) / 2);
            SetLeft(LineHolder, 0);
            if (below) { SetTop(Pill, 0); SetTop(LineHolder, PILL_H + 2); }
            else { SetTop(LineHolder, 0); SetTop(Pill, LINE_H); }
        }

        public void Say(string text, Color colour)
        {
            Line.Text = text;
            Line.Foreground = Ink.B(colour);
            Band.Visibility = string.IsNullOrEmpty(text) ? Visibility.Hidden : Visibility.Visible;
        }

        /// STYLE white while an Auto correct model is chosen, green while it styles; COPY white while a take waits for it
        /// (it landed in no text box), green while it copies; grey otherwise.
        public void Light(bool autoCorrect, bool styling, bool unlanded, bool copying)
        {
            StyleBtn.Tint = styling ? Ink.Green : autoCorrect ? Ink.Lit : Ink.Dim;
            Copy.Tint = copying ? Ink.Green : unlanded ? Ink.Lit : Ink.Dim;
        }

        /// --pill-shot: the face drawn into a PNG at 2x on a grey ground, never on the screen.
        public void SavePng(string path)
        {
            var back = new Border { Background = new SolidColorBrush(Color.FromRgb(0x8C, 0x8C, 0x8C)), Padding = new Thickness(0, 8, 0, 8), Child = this };
            back.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            back.Arrange(new Rect(back.DesiredSize));
            back.UpdateLayout();
            var bmp = new RenderTargetBitmap((int)(back.ActualWidth * 2), (int)(back.ActualHeight * 2), 192, 192, PixelFormats.Pbgra32);
            bmp.Render(back);
            var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(bmp));
            using var f = File.Create(path); enc.Save(f);
            back.Child = null;
        }
    }

    public sealed class PillWindow : Window
    {
        public readonly PillFace Face;
        IntPtr hwnd;
        public IntPtr Handle => hwnd;

        public PillWindow(PillFace face)
        {
            Face = face;
            Title = Paths.Name;
            WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
            ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; Topmost = true; ShowActivated = false; Focusable = false;
            SizeToContent = SizeToContent.WidthAndHeight;
            Content = face;
            SourceInitialized += (s, e) =>
            {
                hwnd = new WindowInteropHelper(this).Handle;
                int ex = Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE);
                Native.SetWindowLong(hwnd, Native.GWL_EXSTYLE, (ex | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW | Native.WS_EX_TOPMOST) & ~Native.WS_EX_APPWINDOW);
                HwndSource.FromHwnd(hwnd).AddHook(Hook);
            };
            face.MouseLeftButtonDown += DragDown;
            face.MouseMove += DragMove;
            face.MouseLeftButtonUp += DragUp;
        }

        IntPtr Hook(IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled)
        {
            if (msg == 0x0021) { handled = true; return (IntPtr)3; }            // WM_MOUSEACTIVATE → MA_NOACTIVATE
            HotKey.Hook(h, msg, w, l, ref handled);
            return IntPtr.Zero;
        }

        // dragging by any part that is not a button; on the status line a short click (under 0.3 s and 4 px) flips it
        Native.POINT downMouse; Native.RECT downRect; DateTime downAt; bool dragging, moved, onLine;
        void DragDown(object s, MouseButtonEventArgs e)
        {
            Native.GetCursorPos(out downMouse); Native.GetWindowRect(hwnd, out downRect);
            downAt = DateTime.Now; dragging = true; moved = false;
            onLine = Face.Band.IsMouseOver;
            Face.CaptureMouse();
        }
        void DragMove(object s, MouseEventArgs e)
        {
            if (!dragging) return;
            Native.GetCursorPos(out var m);
            int dx = m.X - downMouse.X, dy = m.Y - downMouse.Y;
            if (!moved && Math.Abs(dx) < 4 && Math.Abs(dy) < 4) return;
            moved = true;
            Native.SetWindowPos(hwnd, IntPtr.Zero, downRect.Left + dx, downRect.Top + dy, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE);
        }
        void DragUp(object s, MouseButtonEventArgs e)
        {
            if (!dragging) return;
            dragging = false; Face.ReleaseMouseCapture();
            if (moved) { Prefs.Current.X = Left; Prefs.Current.Y = Top; Prefs.Current.Save(); }
            else if (onLine && (DateTime.Now - downAt).TotalSeconds < 0.3) Face.LineClicked?.Invoke();
        }

        /// Shows the blob without taking the focus.
        public void ShowQuietly()
        {
            if (!IsVisible) Show();
            Topmost = false; Topmost = true;
        }
    }
}
