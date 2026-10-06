// FormRepair: rewrites Deflate-compressed eApp form pages as PackBits TIFF, which Wine's image codec reads.
// Decodes the Deflate data itself (.NET inflater). No other decoder is involved.
//   FormRepair.exe <formsDir>            repair in place; originals kept in <formsDir>\_deflate-original
//   FormRepair.exe --list <formsDir>     only list the pages it would repair
//   FormRepair.exe --dump <tif> <out>    raw 32bpp render of every frame through GDI+ (verification)
using System; using System.IO; using System.IO.Compression; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
class FormRepair {
  class Page { public uint W, H, Rps; public int Bps = 1, Spp = 1, Comp = 1, Photo = 1, Fill = 1, Pred = 1, Planar = 1, ResUnit = 2, PageNo = -1, PageTot = -1; public uint[] SOff, SCnt; public uint XrN = 300, XrD = 1, YrN = 300, YrD = 1; }
  static int Main(string[] a) {
    if (a.Length >= 3 && a[0] == "--dump") { Dump(a[1], a[2]); return 0; }
    bool list = a.Length >= 2 && a[0] == "--list"; string dir = list ? a[1] : a[0];
    string orig = Path.Combine(dir, "_deflate-original"); int fixedN = 0, skipped = 0, failed = 0;
    foreach (var f in Directory.GetFiles(dir)) {
      string ext = Path.GetExtension(f).ToLowerInvariant(); if (ext != ".tif" && ext != ".tiff") continue;
      byte[] t; List<Page> pages; try { t = File.ReadAllBytes(f); pages = ReadPages(t); } catch { skipped++; continue; }
      bool deflate = pages.Count > 0; foreach (var p in pages) if (p.Comp != 8 && p.Comp != 32946) deflate = false;
      if (!deflate) { skipped++; continue; }
      if (list) { Console.WriteLine("DEFLATE " + Path.GetFileName(f) + " pages=" + pages.Count + " bps=" + pages[0].Bps); continue; }
      string tmp = f + ".repair.tmp";
      try {
        Write(t, pages, tmp);
        int frames; using (var chk = Image.FromFile(tmp)) frames = chk.GetFrameCount(FrameDimension.Page);
        if (frames != pages.Count) throw new Exception("verify: " + frames + " frames, expected " + pages.Count);
        Directory.CreateDirectory(orig); string keep = Path.Combine(orig, Path.GetFileName(f));
        if (File.Exists(keep)) keep = Path.Combine(orig, Path.GetFileNameWithoutExtension(f) + "." + DateTime.Now.ToString("yyyyMMddHHmmss") + ext);
        File.Move(f, keep); File.Move(tmp, f); fixedN++; Console.WriteLine("FIXED " + Path.GetFileName(f) + " pages=" + pages.Count);
      } catch (Exception e) { failed++; Console.WriteLine("FAIL  " + Path.GetFileName(f) + "  " + e.Message); try { if (File.Exists(tmp)) File.Delete(tmp); } catch { } }
    }
    Console.WriteLine("done fixed=" + fixedN + " skipped=" + skipped + " failed=" + failed); return failed == 0 ? 0 : 1;
  }
  static List<Page> ReadPages(byte[] t) {
    bool le = t[0] == (byte)'I'; if ((le ? t[2] : t[3]) != 42) throw new Exception("not a TIFF");
    Func<int, int> u16 = o => le ? t[o] | (t[o + 1] << 8) : (t[o] << 8) | t[o + 1];
    Func<int, uint> u32 = o => le ? (uint)(t[o] | (t[o + 1] << 8) | (t[o + 2] << 16) | (t[o + 3] << 24)) : (uint)((t[o] << 24) | (t[o + 1] << 16) | (t[o + 2] << 8) | t[o + 3]);
    var pages = new List<Page>(); uint ifd = u32(4); int guard = 0;
    while (ifd != 0 && ifd + 2 <= t.Length && guard++ < 500) {
      int n = u16((int)ifd); var p = new Page();
      for (int i = 0; i < n; i++) {
        int e = (int)ifd + 2 + 12 * i; int tag = u16(e), typ = u16(e + 2); uint cnt = u32(e + 4);
        int tsz = typ == 3 ? 2 : typ == 4 ? 4 : typ == 5 ? 8 : 1; int vo = cnt * (uint)tsz <= 4 ? e + 8 : (int)u32(e + 8);
        Func<int, uint> val = k => typ == 3 ? (uint)u16(vo + 2 * k) : typ == 1 ? t[vo + k] : u32(vo + 4 * k);
        switch (tag) {
          case 256: p.W = val(0); break; case 257: p.H = val(0); break; case 258: p.Bps = (int)val(0); break; case 259: p.Comp = (int)val(0); break;
          case 262: p.Photo = (int)val(0); break; case 266: p.Fill = (int)val(0); break; case 277: p.Spp = (int)val(0); break; case 278: p.Rps = val(0); break;
          case 273: p.SOff = new uint[cnt]; for (int k = 0; k < cnt; k++) p.SOff[k] = val(k); break;
          case 279: p.SCnt = new uint[cnt]; for (int k = 0; k < cnt; k++) p.SCnt[k] = val(k); break;
          case 282: p.XrN = u32(vo); p.XrD = u32(vo + 4); break; case 283: p.YrN = u32(vo); p.YrD = u32(vo + 4); break;
          case 284: p.Planar = (int)val(0); break; case 296: p.ResUnit = (int)val(0); break; case 317: p.Pred = (int)val(0); break;
          case 297: p.PageNo = (int)val(0); if (cnt > 1) p.PageTot = (int)val(1); break;
        }
      }
      if (p.Rps == 0 || p.Rps > p.H) p.Rps = p.H; pages.Add(p); ifd = u32((int)ifd + 2 + 12 * n);
    }
    return pages;
  }
  static byte[] Inflate(byte[] t, uint off, uint cnt, int expect) {
    int skip = (cnt >= 2 && (t[off] & 0x0F) == 8 && (((t[off] << 8) | t[off + 1]) % 31) == 0) ? 2 : 0;
    using (var ms = new MemoryStream(t, (int)(off + skip), (int)(cnt - skip))) using (var ds = new DeflateStream(ms, CompressionMode.Decompress)) {
      var buf = new byte[expect]; int got = 0; while (got < expect) { int r = ds.Read(buf, got, expect - got); if (r <= 0) break; got += r; }
      if (got < expect) throw new Exception("short inflate " + got + "/" + expect); return buf;
    }
  }
  static void Write(byte[] t, List<Page> pages, string path) {
    using (var fs = new FileStream(path, FileMode.Create)) using (var w = new BinaryWriter(fs)) {
      w.Write((byte)'I'); w.Write((byte)'I'); w.Write((ushort)42); w.Write((uint)0); long prevNext = 4;
      for (int pi = 0; pi < pages.Count; pi++) {
        var p = pages[pi];
        if (p.Spp != 1 || (p.Bps != 1 && p.Bps != 8) || p.Planar != 1 || (p.Pred != 1 && p.Bps != 8) || p.SOff == null || p.SCnt == null) throw new Exception("unsupported layout on page " + pi);
        int rowBytes = (int)((p.W * (uint)p.Bps + 7) / 8); long stripOff = fs.Position; var packed = new MemoryStream(); uint rowsDone = 0;
        for (int s = 0; s < p.SOff.Length && rowsDone < p.H; s++) {
          uint rows = Math.Min(p.Rps, p.H - rowsDone); var raw = Inflate(t, p.SOff[s], p.SCnt[s], (int)(rows * rowBytes));
          for (uint y = 0; y < rows; y++) {
            int o = (int)(y * rowBytes);
            if (p.Fill == 2) for (int x = 0; x < rowBytes; x++) { byte b = raw[o + x]; b = (byte)(((b * 0x0802u & 0x22110u) | (b * 0x8020u & 0x88440u)) * 0x10101u >> 16); raw[o + x] = b; }
            if (p.Pred == 2) for (int x = 1; x < rowBytes; x++) raw[o + x] += raw[o + x - 1];
            PackRow(raw, o, rowBytes, packed);
          }
          rowsDone += rows;
        }
        packed.Position = 0; packed.CopyTo(fs); long stripLen = fs.Position - stripOff; if ((fs.Position & 1) == 1) w.Write((byte)0);
        long xr = fs.Position; w.Write(p.XrN); w.Write(p.XrD); long yr = fs.Position; w.Write(p.YrN); w.Write(p.YrD);
        long ifd = fs.Position; fs.Position = prevNext; w.Write((uint)ifd); fs.Position = ifd;
        int entries = 14 + (p.PageNo >= 0 ? 1 : 0); w.Write((ushort)entries);
        En(w, 256, 4, 1, p.W); En(w, 257, 4, 1, p.H); En(w, 258, 3, 1, (uint)p.Bps); En(w, 259, 3, 1, 32773); En(w, 262, 3, 1, (uint)p.Photo); En(w, 266, 3, 1, 1);
        En(w, 273, 4, 1, (uint)stripOff); En(w, 277, 3, 1, 1); En(w, 278, 4, 1, p.H); En(w, 279, 4, 1, (uint)stripLen); En(w, 282, 5, 1, (uint)xr); En(w, 283, 5, 1, (uint)yr); En(w, 284, 3, 1, 1); En(w, 296, 3, 1, (uint)p.ResUnit);
        if (p.PageNo >= 0) { w.Write((ushort)297); w.Write((ushort)3); w.Write((uint)2); w.Write((ushort)p.PageNo); w.Write((ushort)(p.PageTot >= 0 ? p.PageTot : pages.Count)); }
        prevNext = fs.Position; w.Write((uint)0);
      }
    }
  }
  static void En(BinaryWriter w, int tag, int type, uint count, uint val) { w.Write((ushort)tag); w.Write((ushort)type); w.Write(count); if (type == 3 && count == 1) { w.Write((ushort)val); w.Write((ushort)0); } else w.Write(val); }
  static void PackRow(byte[] b, int off, int len, Stream o) {
    int i = 0; while (i < len) {
      int run = 1; while (i + run < len && b[off + i + run] == b[off + i] && run < 128) run++;
      if (run >= 2) { o.WriteByte((byte)(257 - run)); o.WriteByte(b[off + i]); i += run; continue; }
      int lit = 1; while (i + lit < len && lit < 128 && !(i + lit + 1 < len && b[off + i + lit] == b[off + i + lit + 1])) lit++;
      o.WriteByte((byte)(lit - 1)); o.Write(b, off + i, lit); i += lit;
    }
  }
  static void Dump(string tif, string outPath) {
    using (var img = Image.FromFile(tif)) using (var o = new FileStream(outPath, FileMode.Create)) {
      int frames = 1; try { frames = img.GetFrameCount(FrameDimension.Page); } catch { }
      for (int p = 0; p < frames; p++) { if (frames > 1) img.SelectActiveFrame(FrameDimension.Page, p);
        using (var n = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb)) { using (var g = Graphics.FromImage(n)) g.DrawImage(img, 0, 0, img.Width, img.Height);
          var bd = n.LockBits(new Rectangle(0, 0, n.Width, n.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb); var buf = new byte[bd.Stride * n.Height]; Marshal.Copy(bd.Scan0, buf, 0, buf.Length); n.UnlockBits(bd); o.Write(buf, 0, buf.Length); } }
      Console.WriteLine("dumped frames=" + frames + " " + img.Width + "x" + img.Height);
    }
  }
}
