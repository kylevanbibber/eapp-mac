using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;

// Mirrors eApp: Ail.FormFillerControls.FormFillerTabControl.GetImage(frame) -> Image.FromFile(filename, useEmbeddedColorManagement)
class CodecTest {
  static void Main(string[] args) {
    string dir = args.Length > 0 ? args[0] : @"C:\codec";
    foreach (var f in Directory.GetFiles(dir)) {
      string name = Path.GetFileName(f);
      if (name.EndsWith(".exe") || name.EndsWith(".cs") || name.EndsWith(".txt")) continue;
      foreach (bool icm in new[] { false, true }) {
        try {
          using (var img = Image.FromFile(f, icm)) {
            int frames = 1;
            try { frames = img.GetFrameCount(FrameDimension.Page); } catch { }
            string extra = "";
            if (frames > 1) { try { img.SelectActiveFrame(FrameDimension.Page, 1); extra = " frame1=ok"; } catch (Exception e) { extra = " frame1=FAIL:" + e.Message; } }
            Console.WriteLine("OK    " + name + (icm ? " (icm)" : "      ") + "  " + img.Width + "x" + img.Height + " " + img.PixelFormat + " frames=" + frames + extra);
          }
        } catch (Exception e) {
          Console.WriteLine("FAIL  " + name + (icm ? " (icm)" : "      ") + "  " + e.GetType().Name + ": " + e.Message);
        }
      }
    }
  }
}
