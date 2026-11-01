// v3, the duck (Marko, 1.11.2026: "reduce audio output while it's listening to the microphone to 6%. When listening is
// done, it brings it back to old value"): the default speakers' master volume through Windows' own Core Audio
// (IAudioEndpointVolume), no extra package. The level to go back to is kept in duck.txt too, so a crash mid-take is put
// right at the next start. A level already below 6 % is left as it is.
using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

namespace MantraVoiceToText
{
    public static class Duck
    {
        public const float Level = 0.06f;
        static string Saved => Path.Combine(Paths.Home, "duck.txt");

        public static bool IsDucked => File.Exists(Saved);

        public static void Down()
        {
            if (!Prefs.Current.Duck || IsDucked) return;
            Mta(() => { DownNow(); return 0; }, "down");
        }

        static void DownNow()
        {
            try
            {
                var v = Endpoint();
                if (v == null) return;
                v.GetMasterVolumeLevelScalar(out float now);
                File.WriteAllText(Saved, now.ToString(CultureInfo.InvariantCulture));
                if (now > Level) v.SetMasterVolumeLevelScalar(Level, Guid.Empty);
                Log.Write($"duck: speakers {now * 100:0} % -> {Math.Min(now, Level) * 100:0} %");
            }
            catch (Exception e) { Log.Write("duck: " + e.Message); }
        }

        public static void Up()
        {
            if (!IsDucked) return;
            Mta(() => { UpNow(); return 0; }, "up");
        }

        static void UpNow()
        {
            try
            {
                float was = float.Parse(File.ReadAllText(Saved).Trim(), CultureInfo.InvariantCulture);
                File.Delete(Saved);
                var v = Endpoint();
                if (v == null) return;
                v.SetMasterVolumeLevelScalar(was, Guid.Empty);
                Log.Write($"duck: speakers back to {was * 100:0} %");
            }
            catch (Exception e) { Log.Write("duck: " + e.Message); try { File.Delete(Saved); } catch { } }
        }

        public static float? Now()
        {
            return Mta<float?>(() =>
            {
                try { var v = Endpoint(); if (v == null) return null; v.GetMasterVolumeLevelScalar(out float x); return x; }
                catch (Exception e) { Log.Write("duck: " + e.Message); return null; }
            }, "read");
        }

        /// every Core Audio call on a pool (MTA) thread, at most 2 s: the speakers are never worth a frozen app
        static T Mta<T>(Func<T> f, string what)
        {
            var t = System.Threading.Tasks.Task.Run(f);
            if (t.Wait(2000)) return t.Result;
            Log.Write("duck: " + what + " did not answer in 2 s");
            return default;
        }

        static IAudioEndpointVolume Endpoint()
        {
            var en = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            if (en.GetDefaultAudioEndpoint(0 /* eRender */, 1 /* eMultimedia */, out IMMDevice dev) != 0 || dev == null) return null;
            var iid = typeof(IAudioEndpointVolume).GUID;
            if (dev.Activate(ref iid, 1 /* CLSCTX_INPROC_SERVER */, IntPtr.Zero, out object o) != 0) return null;
            return o as IAudioEndpointVolume;
        }

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }

        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator
        {
            [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
            [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        }

        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice
        {
            [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        }

        [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioEndpointVolume
        {
            [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
            [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
            [PreserveSig] int GetChannelCount(out uint count);
            [PreserveSig] int SetMasterVolumeLevel(float levelDB, [In, MarshalAs(UnmanagedType.LPStruct)] Guid eventContext);
            [PreserveSig] int SetMasterVolumeLevelScalar(float level, [In, MarshalAs(UnmanagedType.LPStruct)] Guid eventContext);
            [PreserveSig] int GetMasterVolumeLevel(out float levelDB);
            [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        }
    }
}
