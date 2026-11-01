# Requests, word for word

## 1.11.2026

> Please confirm that it works. It is ready to be updated and published on the website as well.

(Asked: Full public release.)

> Please also make a Windows app.

Decided by Marko: free signing on both (Mantra Apps on the Mac with the "open the first time" steps on the site; Windows unsigned with "More info → Run anyway"); Windows in C# .NET + whisper.cpp (Whisper.net), built and tested in the Parallels Windows 11.

> in this app, like in any app which downloads, you just need to always resume downloads. Even if the user closes the application and you open, it will continue where it left off so the user doesn't need to do it again

- The model download resumes: a cut connection retries from where it stopped, and a download interrupted by quitting continues by itself at the next start, from the bytes already there. Mac and Windows. **Status:** Mac done 1.11.2026 (killed at 573,055,166 bytes, the next start went on from that byte, checksum right); Windows with the Windows agent
