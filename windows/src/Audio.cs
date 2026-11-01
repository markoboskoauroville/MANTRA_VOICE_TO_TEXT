// The ears' input: the microphone at 16 kHz mono (NAudio's WaveIn), the loudest peak of the take for the silence gate,
// and the eleven bands of the voice meter (an FFT of the last 1024 samples, as the Mac blob's meter).
using System;
using System.Collections.Generic;
using System.Linq;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace MantraVoiceToText
{
    public sealed class Recorder : IDisposable
    {
        public const int Rate = 16000;
        WaveInEvent wave;
        readonly List<float> samples = new List<float>();
        readonly object gate = new object();
        readonly float[] ring = new float[Bands.N];
        int ringFilled;
        public bool Recording { get; private set; }
        bool paused;
        public bool Paused                                  // v3: paused is not listening, the speakers come back
        {
            get => paused;
            set { paused = value; if (Recording) { if (value) Duck.Up(); else Duck.Down(); } }
        }
        public float Peak { get; private set; }           // linear, 0…1, of the whole take
        public double Seconds { get { lock (gate) return samples.Count / (double)Rate; } }
        public string Error { get; private set; }

        public static List<string> Devices()
        {
            var r = new List<string>();
            try { for (int i = 0; i < WaveInEvent.DeviceCount; i++) r.Add(WaveInEvent.GetCapabilities(i).ProductName); } catch { }
            return r;
        }

        static int DeviceNumber(string name)
        {
            if (string.IsNullOrEmpty(name)) return -1;                       // WAVE_MAPPER: the Windows default
            var d = Devices();
            int i = d.FindIndex(x => x == name);
            return i >= 0 ? i : -1;
        }

        public bool Start(string device)
        {
            Error = null;
            lock (gate) { samples.Clear(); ringFilled = 0; Array.Clear(ring); }
            Peak = 0; paused = false;
            try
            {
                if (WaveInEvent.DeviceCount == 0) { Error = "no microphone found"; return false; }
                wave = new WaveInEvent { DeviceNumber = DeviceNumber(device), WaveFormat = new WaveFormat(Rate, 16, 1), BufferMilliseconds = 40, NumberOfBuffers = 4 };
                wave.DataAvailable += OnData;
                wave.StartRecording();
                Recording = true;
                Duck.Down();                                 // v3: the speakers at 6 % while it listens
                return true;
            }
            catch (Exception e)
            {
                Error = e.Message; Log.Write("microphone did not start: " + e.Message);
                try { wave?.Dispose(); } catch { }
                wave = null;
                return false;
            }
        }

        void OnData(object s, WaveInEventArgs e)
        {
            int n = e.BytesRecorded / 2;
            lock (gate)
            {
                for (int i = 0; i < n; i++)
                {
                    float v = BitConverter.ToInt16(e.Buffer, i * 2) / 32768f;
                    ring[ringFilled % Bands.N] = v; ringFilled++;
                    if (Paused) continue;
                    samples.Add(v);
                    float a = Math.Abs(v);
                    if (a > Peak) Peak = a;
                }
            }
        }

        /// The bands of the newest 1024 samples, in dB (a full-scale sine = 0), or null before there are enough.
        public double[] Meter()
        {
            float[] last = new float[Bands.N];
            lock (gate)
            {
                if (ringFilled < Bands.N / 2 || Paused) return null;
                int start = ringFilled;
                for (int i = 0; i < Bands.N; i++) last[i] = ring[(start + i) % Bands.N];
            }
            return Bands.Analyse(last, Rate);
        }

        public float[] Stop()
        {
            Duck.Up();
            try { wave?.StopRecording(); } catch { }
            try { wave?.Dispose(); } catch { }
            wave = null;
            Recording = false;
            lock (gate) return samples.ToArray();
        }

        public void Dispose() { Stop(); }

        public static double Db(float linear) => linear <= 0 ? -140 : 20 * Math.Log10(linear);
    }

    public static class Bands
    {
        public const int N = 1024;
        static readonly double[] edges = Enumerable.Range(0, 12).Select(i => 80 * Math.Pow(7600.0 / 80, i / 11.0)).ToArray();
        public static readonly double[] Centres = Enumerable.Range(0, 11).Select(i => 80 * Math.Pow(7600.0 / 80, (i + 0.5) / 11)).ToArray();
        static readonly double[] hann = Enumerable.Range(0, N).Select(i => 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (N - 1))).ToArray();

        public static double[] Analyse(float[] x, int rate)
        {
            var re = new double[N]; var im = new double[N];
            for (int i = 0; i < N; i++) re[i] = x[i] * hann[i];
            Fft(re, im);
            // a full-scale sine through a Hann window (peak 1): |X| = N/4 at its bin, its power spread over 1.5 bins
            double full = (N / 4.0) * (N / 4.0) * 1.5, hz = rate / (double)N;
            var r = new double[11];
            for (int b = 0; b < 11; b++)
            {
                int lo = Math.Max(1, (int)Math.Ceiling(edges[b] / hz)), hi = Math.Min(N / 2 - 1, (int)Math.Floor(edges[b + 1] / hz));
                double sum = 0;
                for (int k = lo; k <= hi; k++) sum += re[k] * re[k] + im[k] * im[k];
                r[b] = sum > 0 ? 10 * Math.Log10(sum / full) : -140;
            }
            return r;
        }

        static void Fft(double[] re, double[] im)
        {
            int n = re.Length;
            for (int i = 1, j = 0; i < n; i++)
            {
                int bit = n >> 1;
                for (; (j & bit) != 0; bit >>= 1) j ^= bit;
                j ^= bit;
                if (i < j) { (re[i], re[j]) = (re[j], re[i]); (im[i], im[j]) = (im[j], im[i]); }
            }
            for (int len = 2; len <= n; len <<= 1)
            {
                double ang = -2 * Math.PI / len, wr = Math.Cos(ang), wi = Math.Sin(ang);
                for (int i = 0; i < n; i += len)
                {
                    double cr = 1, ci = 0;
                    for (int k = 0; k < len / 2; k++)
                    {
                        int a = i + k, b = i + k + len / 2;
                        double tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr;
                        re[b] = re[a] - tr; im[b] = im[a] - ti; re[a] += tr; im[a] += ti;
                        double ncr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = ncr;
                    }
                }
            }
        }
    }

    public static class WavFile
    {
        /// Any WAV, read as 16 kHz mono floats (the same samples the microphone gives the ears).
        public static float[] Read16kMono(string path)
        {
            using var reader = new WaveFileReader(path);
            ISampleProvider p = reader.ToSampleProvider();
            if (p.WaveFormat.Channels == 2) p = new StereoToMonoSampleProvider(p);
            else if (p.WaveFormat.Channels > 2) throw new InvalidOperationException("only mono or stereo files");
            if (p.WaveFormat.SampleRate != Recorder.Rate) p = new WdlResamplingSampleProvider(p, Recorder.Rate);
            var all = new List<float>(Recorder.Rate * 30);
            var buf = new float[Recorder.Rate];
            int n;
            while ((n = p.Read(buf, 0, buf.Length)) > 0) for (int i = 0; i < n; i++) all.Add(buf[i]);
            return all.ToArray();
        }
    }
}
