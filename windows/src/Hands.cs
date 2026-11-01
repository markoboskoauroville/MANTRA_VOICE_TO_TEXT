// The hands: the words go into the window that has the keyboard focus (clipboard + Ctrl+V through SendInput, the
// clipboard's text put back afterwards); STYLE reads and writes the focused text box through UI Automation; the global hotkey.
// The blob never takes the focus, so "the focused window" is always the app the speaker was typing in.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace MantraVoiceToText
{
    static class Native
    {
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)]
        public struct GUITHREADINFO { public int cbSize, flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }
        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
        [StructLayout(LayoutKind.Explicit)]
        public struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT { public uint type; public InputUnion u; }

        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO info);
        [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);
        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
        [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
        [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
        [DllImport("kernel32.dll")] public static extern bool AttachConsole(int pid);
        public const int GWL_EXSTYLE = -20, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOOLWINDOW = 0x80, WS_EX_TOPMOST = 0x8, WS_EX_APPWINDOW = 0x40000;
        public const uint SWP_NOSIZE = 1, SWP_NOZORDER = 4, SWP_NOACTIVATE = 0x10;
        public const uint KEYUP = 2, UNICODE = 4;
        public const uint MOD_ALT = 1, MOD_CONTROL = 2, MOD_SHIFT = 4, MOD_WIN = 8, MOD_NOREPEAT = 0x4000;

        public static string ClassOf(IntPtr h) { var s = new System.Text.StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }

        static INPUT Key(ushort vk, bool up) => new INPUT { type = 1, u = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = up ? KEYUP : 0 } } };

        static void ReleaseHeld(List<INPUT> list, ushort except = 0)
        {
            foreach (var held in new ushort[] { 0x10, 0x11, 0x12, 0x5B, 0x5C })      // Shift, Ctrl, Alt, LWin, RWin
                if (held != except && (GetAsyncKeyState(held) & 0x8000) != 0) list.Add(Key(held, true));
        }

        /// A chord such as Ctrl+V: modifiers the speaker still holds are released first, so V is not Ctrl+Shift+V.
        public static void Chord(ushort mod, ushort key)
        {
            var list = new List<INPUT>();
            ReleaseHeld(list, mod);
            list.Add(Key(mod, false)); list.Add(Key(key, false)); list.Add(Key(key, true)); list.Add(Key(mod, true));
            SendInput((uint)list.Count, list.ToArray(), Marshal.SizeOf<INPUT>());
        }
    }

    public enum Landing { Typed, Nowhere }

    public static class Hands
    {
        static readonly int myPid = Environment.ProcessId;

        /// The focused element of the foreground app, when it takes text. Asked off the UI thread (UI Automation calls
        /// into the other process).
        public static (bool editable, string what) FocusTakesText()
        {
            var fg = Native.GetForegroundWindow();
            if (fg == IntPtr.Zero) return (false, "no window has the focus");
            Native.GetWindowThreadProcessId(fg, out var pid);
            if (pid == myPid) return (false, "the focus is on this app");
            string who = "";
            try { who = Process.GetProcessById((int)pid).ProcessName + "/"; } catch { }
            var cls = Native.ClassOf(fg);
            who += cls;
            if (fg == Native.GetShellWindow() || cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd") return (false, "the desktop has the focus");
            // a terminal (Windows Terminal, the old console) takes Ctrl+V though its text area is not an Edit for UI Automation
            if (cls == "CASCADIA_HOSTING_WINDOW_CLASS" || cls == "ConsoleWindowClass" || cls == "PseudoConsoleWindow") return (true, "terminal " + who);
            var tid = Native.GetWindowThreadProcessId(fg, out _);
            var gti = new Native.GUITHREADINFO { cbSize = Marshal.SizeOf<Native.GUITHREADINFO>() };
            bool caret = Native.GetGUIThreadInfo(tid, ref gti) && gti.hwndCaret != IntPtr.Zero;
            try
            {
                var el = AutomationElement.FocusedElement;
                if (el != null)
                {
                    var ct = el.Current.ControlType;
                    if (ct == ControlType.Edit || ct == ControlType.Document) return (true, ct.ProgrammaticName + " in " + who);
                    if (el.TryGetCurrentPattern(ValuePattern.Pattern, out var vp) && !((ValuePattern)vp).Current.IsReadOnly
                        && ct != ControlType.Button && ct != ControlType.ListItem && ct != ControlType.TreeItem) return (true, "value " + ct.ProgrammaticName);
                    if (caret) return (true, "caret in " + ct.ProgrammaticName);
                    return (false, ct.ProgrammaticName.Replace("ControlType.", "") + " has the focus in " + who + ", not a text box");
                }
            }
            catch (Exception e) { Log.Write("focus: UI Automation failed: " + e.Message); }
            return caret ? (true, "caret") : (false, "no text box has the focus");
        }

        /// Puts the text where the cursor is: clipboard + Ctrl+V, then the clipboard as it was. (Unicode key events were
        /// tried first and garbled the text in Windows 11 Notepad: LESSONS.md.) Called on the UI thread.
        public static async Task<Landing> Insert(string text)
        {
            var (ok, what) = await Task.Run(FocusTakesText);
            Log.Write("focus: " + what);
            if (!ok) return Landing.Nowhere;
            await Paste(text);
            return Landing.Typed;
        }

        public static async Task Paste(string text)
        {
            var saved = SaveClipboard();
            SetClipboard(text);
            await Task.Delay(30);
            Native.Chord(0x11, 0x56);                        // Ctrl+V
            await Task.Delay(400);                           // the target reads the clipboard before it is given back
            RestoreClipboard(saved);
        }

        // Only the text formats are kept and given back: asking for every format made Windows render each one (in the VM
        // the shared Mac clipboard took 30 s), and a picture or files on the clipboard are rare while dictating.
        static readonly string[] keep = { DataFormats.UnicodeText, DataFormats.Rtf, DataFormats.Html };
        static Dictionary<string, object> SaveClipboard()
        {
            var d = new Dictionary<string, object>();
            try
            {
                var o = Clipboard.GetDataObject();
                if (o == null) return d;
                foreach (var f in keep)
                {
                    try { if (o.GetDataPresent(f, false)) { var v = o.GetData(f, false); if (v != null) d[f] = v; } } catch { }
                }
            }
            catch { }
            return d;
        }

        static void RestoreClipboard(Dictionary<string, object> d)
        {
            try
            {
                if (d.Count == 0) return;                    // nothing that was text: the dictated words stay there
                var o = new DataObject();
                foreach (var kv in d) { try { o.SetData(kv.Key, kv.Value); } catch { } }
                Clipboard.SetDataObject(o, true);
            }
            catch (Exception e) { Log.Write("clipboard not restored: " + e.Message); }
        }

        public static void SetClipboard(string text)
        {
            for (int i = 0; i < 10; i++)
            {
                try { Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), true); return; }
                catch (Exception e) { if (i == 9) Log.Write("clipboard: could not be set: " + e.Message); Thread.Sleep(40); }
            }
        }

        // ---------- STYLE: the focused text box ----------

        public sealed class Box
        {
            public AutomationElement Element;
            public string Text = "";
            public bool Selection;
            public bool CanSetValue;
            public string What = "";
        }

        /// The focused box's selection, else its whole text; null with the reason when there is no text box.
        public static (Box box, string why) ReadFocused()
        {
            var (ok, what) = FocusTakesText();
            if (!ok) return (null, "click into the text box you want styled, then STYLE");
            try
            {
                var el = AutomationElement.FocusedElement;
                var box = new Box { Element = el };
                TextPattern tp = null;
                if (el.TryGetCurrentPattern(TextPattern.Pattern, out var t)) tp = (TextPattern)t;
                ValuePattern vp = null;
                if (el.TryGetCurrentPattern(ValuePattern.Pattern, out var v)) vp = (ValuePattern)v;
                box.CanSetValue = vp != null && !vp.Current.IsReadOnly;
                if (tp != null)
                {
                    var sel = tp.GetSelection();
                    var s = string.Concat(sel.Select(r => r.GetText(-1)));
                    if (s.Trim().Length > 0) { box.Text = s; box.Selection = true; box.What = "the selection"; return (box, null); }
                }
                if (vp != null) { box.Text = vp.Current.Value ?? ""; box.What = "the text box"; }
                else if (tp != null) { box.Text = tp.DocumentRange.GetText(-1) ?? ""; box.What = "the text box"; }
                else return (null, "this text box cannot be read: select its text, Ctrl+C, then STYLE works on the clipboard copy");
                return (box, null);
            }
            catch (Exception e) { return (null, "the text box could not be read (" + e.Message + ")"); }
        }

        /// Writes the styled text back: over the selection (paste), into the value, or the whole text replaced (Ctrl+A,
        /// paste). Returns what happened; "clipboard" when it could not write.
        public static async Task<string> WriteBack(Box box, string styled)
        {
            try
            {
                if (box.Selection) { await Paste(styled); return "selection replaced"; }
                if (box.CanSetValue)
                {
                    bool set = await Task.Run(() =>
                    {
                        try { ((ValuePattern)box.Element.GetCurrentPattern(ValuePattern.Pattern)).SetValue(styled); return true; }
                        catch { return false; }
                    });
                    if (set) return "text replaced";
                }
                Native.Chord(0x11, 0x41);                     // Ctrl+A, then the paste replaces everything
                await Task.Delay(60);
                await Paste(styled);
                return "text replaced";
            }
            catch (Exception e)
            {
                Log.Write("STYLE write back failed: " + e.Message);
                SetClipboard(styled);
                return "clipboard";
            }
        }
    }

    /// A global hotkey (RegisterHotKey on the blob's own window).
    public sealed class HotKey : IDisposable
    {
        static int nextId = 1;
        readonly IntPtr hwnd; readonly int id; readonly Action action;
        public bool Ok { get; }
        static readonly Dictionary<int, HotKey> live = new Dictionary<int, HotKey>();

        public HotKey(IntPtr hwnd, string chord, Action action)
        {
            this.hwnd = hwnd; this.action = action; id = nextId++;
            if (!Parse(chord, out var mods, out var vk)) { Ok = false; return; }
            Ok = Native.RegisterHotKey(hwnd, id, mods | Native.MOD_NOREPEAT, vk);
            if (Ok) live[id] = this;
        }

        public static bool Parse(string chord, out uint mods, out uint vk)
        {
            mods = 0; vk = 0;
            if (string.IsNullOrWhiteSpace(chord)) return false;
            var parts = chord.Split('+').Select(p => p.Trim()).ToList();
            foreach (var m in parts.Take(parts.Count - 1))
            {
                switch (m.ToLowerInvariant())
                {
                    case "ctrl": case "control": mods |= Native.MOD_CONTROL; break;
                    case "alt": mods |= Native.MOD_ALT; break;
                    case "shift": mods |= Native.MOD_SHIFT; break;
                    case "win": mods |= Native.MOD_WIN; break;
                    default: return false;
                }
            }
            if (!Enum.TryParse<Key>(parts.Last(), true, out var key)) return false;
            vk = (uint)KeyInterop.VirtualKeyFromKey(key);
            return vk != 0;
        }

        public static IntPtr Hook(IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled)
        {
            if (msg == 0x0312 && live.TryGetValue(w.ToInt32(), out var k)) { handled = true; k.action(); }
            return IntPtr.Zero;
        }

        public void Dispose() { if (Ok) { Native.UnregisterHotKey(hwnd, id); live.Remove(id); } }
    }
}
