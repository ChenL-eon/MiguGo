param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$drawingAsm = [System.Drawing.Bitmap].Assembly.Location
Add-Type -ReferencedAssemblies $drawingAsm -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class MiguIcons {
    public static Bitmap Load(string path) {
        using (var src = Image.FromFile(path)) {
            var bmp = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp)) {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(src, new Rectangle(0, 0, src.Width, src.Height));
            }
            return bmp;
        }
    }

    public static Bitmap Resize(Image src, int size) {
        var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp)) {
            g.CompositingMode = CompositingMode.SourceCopy;
            g.CompositingQuality = CompositingQuality.HighQuality;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.SmoothingMode = SmoothingMode.HighQuality;
            using (var attr = new ImageAttributes()) {
                attr.SetWrapMode(WrapMode.TileFlipXY);
                g.DrawImage(src, new Rectangle(0, 0, size, size), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, attr);
            }
        }
        return bmp;
    }

    // Full-bleed pink gradient used by the Android adaptive background layer.
    public static Bitmap Gradient(int size) {
        var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        var bd = bmp.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        int stride = bd.Stride;
        byte[] buf = new byte[Math.Abs(stride) * size];
        double x1 = 0.172024 * size, y1 = 0.877334 * size;
        double x2 = 0.827967 * size, y2 = 0.122594 * size;
        double dx = x2 - x1, dy = y2 - y1;
        double len2 = dx * dx + dy * dy;
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                double t = ((x + 0.5 - x1) * dx + (y + 0.5 - y1) * dy) / len2;
                if (t < 0) t = 0;
                if (t > 1) t = 1;
                int r = (int)Math.Round(239 + (252 - 239) * t);
                int g = (int)Math.Round(10 + (96 - 10) * t);
                int b = (int)Math.Round(103 + (151 - 103) * t);
                int i = y * stride + x * 4;
                buf[i] = (byte)b;
                buf[i + 1] = (byte)g;
                buf[i + 2] = (byte)r;
                buf[i + 3] = 255;
            }
        }
        Marshal.Copy(buf, 0, bd.Scan0, buf.Length);
        bmp.UnlockBits(bd);
        return bmp;
    }

    // Windows only: bake a rounded-square alpha mask into the master.
    public static Bitmap Rounded(Bitmap src, double radiusFraction) {
        int w = src.Width, h = src.Height;
        float d = (float)(radiusFraction * 2.0 * Math.Min(w, h));
        var dst = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var path = new GraphicsPath()) {
            path.AddArc(0, 0, d, d, 180, 90);
            path.AddArc(w - d, 0, d, d, 270, 90);
            path.AddArc(w - d, h - d, d, d, 0, 90);
            path.AddArc(0, h - d, d, d, 90, 90);
            path.CloseFigure();
            using (var mask = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
                using (var g = Graphics.FromImage(mask)) {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.Clear(Color.Transparent);
                    using (var brush = new SolidBrush(Color.White)) { g.FillPath(brush, path); }
                }
                var sd = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                var md = mask.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                var dd = dst.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                int ss = sd.Stride, ms = md.Stride, ds = dd.Stride;
                byte[] sb = new byte[Math.Abs(ss) * h];
                byte[] mb = new byte[Math.Abs(ms) * h];
                byte[] db = new byte[Math.Abs(ds) * h];
                Marshal.Copy(sd.Scan0, sb, 0, sb.Length);
                Marshal.Copy(md.Scan0, mb, 0, mb.Length);
                for (int y = 0; y < h; y++) {
                    for (int x = 0; x < w; x++) {
                        int si = y * ss + x * 4;
                        int mi = y * ms + x * 4;
                        int di = y * ds + x * 4;
                        int a = sb[si + 3] * mb[mi + 3] / 255;
                        if (a == 0) {
                            db[di] = 0; db[di + 1] = 0; db[di + 2] = 0; db[di + 3] = 0;
                        } else {
                            db[di] = sb[si];
                            db[di + 1] = sb[si + 1];
                            db[di + 2] = sb[si + 2];
                            db[di + 3] = (byte)a;
                        }
                    }
                }
                Marshal.Copy(db, 0, dd.Scan0, db.Length);
                src.UnlockBits(sd);
                mask.UnlockBits(md);
                dst.UnlockBits(dd);
            }
        }
        return dst;
    }

    public static Bitmap Foreground(Bitmap src, int size, double scale) {
        int w = src.Width, h = src.Height;
        var sd = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = sd.Stride;
        byte[] buf = new byte[Math.Abs(stride) * h];
        Marshal.Copy(sd.Scan0, buf, 0, buf.Length);
        src.UnlockBits(sd);

        int n = w * h;
        float[] a = new float[n];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int i = y * stride + x * 4;
                int low = Math.Min(buf[i], Math.Min(buf[i + 1], buf[i + 2]));
                float v = (low - 100f) / 147f;
                if (v < 0f) v = 0f;
                if (v > 1f) v = 1f;
                a[y * w + x] = v;
            }
        }

        bool[] exterior = new bool[n];
        var stack = new System.Collections.Generic.Stack<int>();
        for (int x = 0; x < w; x++) {
            if (a[x] < 0.5f) { exterior[x] = true; stack.Push(x); }
            int b = (h - 1) * w + x;
            if (a[b] < 0.5f) { exterior[b] = true; stack.Push(b); }
        }
        for (int y = 0; y < h; y++) {
            int l = y * w, r = y * w + (w - 1);
            if (a[l] < 0.5f) { exterior[l] = true; stack.Push(l); }
            if (a[r] < 0.5f) { exterior[r] = true; stack.Push(r); }
        }
        while (stack.Count > 0) {
            int idx = stack.Pop();
            int px = idx % w, py = idx / w;
            if (px > 0 && !exterior[idx - 1] && a[idx - 1] < 0.5f) { exterior[idx - 1] = true; stack.Push(idx - 1); }
            if (px < w - 1 && !exterior[idx + 1] && a[idx + 1] < 0.5f) { exterior[idx + 1] = true; stack.Push(idx + 1); }
            if (py > 0 && !exterior[idx - w] && a[idx - w] < 0.5f) { exterior[idx - w] = true; stack.Push(idx - w); }
            if (py < h - 1 && !exterior[idx + w] && a[idx + w] < 0.5f) { exterior[idx + w] = true; stack.Push(idx + w); }
        }

        var mask = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        var md = mask.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        int mstride = md.Stride;
        byte[] mbuf = new byte[Math.Abs(mstride) * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int idx = y * w + x;
                int i = y * stride + x * 4;
                int oi = y * mstride + x * 4;
                float av = a[idx];
                int r, g, b, alpha;
                if (av >= 0.5f) {
                    alpha = (int)Math.Round(av * 255);
                    if (av >= 0.9f) { b = buf[i]; g = buf[i + 1]; r = buf[i + 2]; }
                    else { r = 247; g = 247; b = 247; }
                } else if (exterior[idx]) {
                    if (av <= 0.02f) { alpha = 0; r = 0; g = 0; b = 0; }
                    else { alpha = (int)Math.Round(av * 255); r = 247; g = 247; b = 247; }
                } else {
                    alpha = 255;
                    b = buf[i]; g = buf[i + 1]; r = buf[i + 2];
                }
                mbuf[oi] = (byte)b;
                mbuf[oi + 1] = (byte)g;
                mbuf[oi + 2] = (byte)r;
                mbuf[oi + 3] = (byte)alpha;
            }
        }
        Marshal.Copy(mbuf, 0, md.Scan0, mbuf.Length);
        mask.UnlockBits(md);

        var dst = ScalePremultiplied(mask, size, scale);
        mask.Dispose();
        return dst;
    }

    public static Bitmap ScalePremultiplied(Bitmap src, int canvas, double scale) {
        int w = src.Width, h = src.Height;
        int draw = (int)Math.Round(canvas * scale);
        int off = (canvas - draw) / 2;
        var sd = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = sd.Stride;
        byte[] sb = new byte[Math.Abs(stride) * h];
        Marshal.Copy(sd.Scan0, sb, 0, sb.Length);
        src.UnlockBits(sd);
        var dst = new Bitmap(canvas, canvas, PixelFormat.Format32bppArgb);
        var dd = dst.LockBits(new Rectangle(0, 0, canvas, canvas), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        int dstride = dd.Stride;
        byte[] db = new byte[Math.Abs(dstride) * canvas];
        for (int ty = 0; ty < draw; ty++) {
            int y0 = ty * h / draw, y1 = (ty + 1) * h / draw;
            if (y1 <= y0) y1 = y0 + 1;
            for (int tx = 0; tx < draw; tx++) {
                int x0 = tx * w / draw, x1 = (tx + 1) * w / draw;
                if (x1 <= x0) x1 = x0 + 1;
                double sa = 0, sr = 0, sg = 0, sbl = 0;
                int cnt = (y1 - y0) * (x1 - x0);
                for (int y = y0; y < y1; y++) {
                    for (int x = x0; x < x1; x++) {
                        int i = y * stride + x * 4;
                        double al = sb[i + 3] / 255.0;
                        sa += al;
                        sr += sb[i + 2] * al;
                        sg += sb[i + 1] * al;
                        sbl += sb[i] * al;
                    }
                }
                int aByte = (int)Math.Round(sa / cnt * 255);
                int r = 0, g = 0, b = 0;
                if (sa > 0) {
                    r = (int)Math.Round(sr / sa);
                    g = (int)Math.Round(sg / sa);
                    b = (int)Math.Round(sbl / sa);
                }
                int di = (off + ty) * dstride + (off + tx) * 4;
                db[di] = (byte)b;
                db[di + 1] = (byte)g;
                db[di + 2] = (byte)r;
                db[di + 3] = (byte)aByte;
            }
        }
        Marshal.Copy(db, 0, dd.Scan0, db.Length);
        dst.UnlockBits(dd);
        return dst;
    }

    public static void WriteIco(string outPath, string[] pngPaths) {
        var payloads = new byte[pngPaths.Length][];
        var sizes = new int[pngPaths.Length];
        for (int i = 0; i < pngPaths.Length; i++) {
            payloads[i] = File.ReadAllBytes(pngPaths[i]);
            using (var img = Image.FromFile(pngPaths[i])) { sizes[i] = img.Width; }
        }
        using (var fs = File.Create(outPath))
        using (var bw = new BinaryWriter(fs)) {
            bw.Write((short)0);
            bw.Write((short)1);
            bw.Write((short)pngPaths.Length);
            int offset = 6 + 16 * pngPaths.Length;
            for (int i = 0; i < pngPaths.Length; i++) {
                bw.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                bw.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                bw.Write((byte)0);
                bw.Write((byte)0);
                bw.Write((short)1);
                bw.Write((short)32);
                bw.Write(payloads[i].Length);
                bw.Write(offset);
                offset += payloads[i].Length;
            }
            for (int i = 0; i < payloads.Length; i++) { bw.Write(payloads[i]); }
        }
    }
}
'@

$root = Split-Path -Parent $PSScriptRoot
$masterPath = Join-Path $root 'assets\icon_png\master\MiguGo_1024.png'
$windowsDir = Join-Path $root 'assets\icon_png\windows_ico_source'
$androidDir = Join-Path $root 'assets\icon_png\android'
$legacyDir = Join-Path $androidDir 'legacy'
$bgDir = Join-Path $androidDir 'adaptive\background'
$fgDir = Join-Path $androidDir 'adaptive\foreground'
foreach ($dir in @($windowsDir, $legacyDir, $bgDir, $fgDir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$master = [MiguIcons]::Load($masterPath)

function Save-Bitmap($bitmap, $path) {
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Write-Output ("saved " + $path)
}

# Windows: rounded plate is part of the artwork because there is no system mask.
$windowsRadius = 0.225
$roundedMasterPath = Join-Path $windowsDir 'MiguGo_windows_1024.png'
Save-Bitmap ([MiguIcons]::Rounded($master, $windowsRadius)) $roundedMasterPath
$roundedMaster = [MiguIcons]::Load($roundedMasterPath)
foreach ($size in @(16, 24, 32, 48, 64, 128, 256, 512)) {
    Save-Bitmap ([MiguIcons]::ScalePremultiplied($roundedMaster, $size, 1.0)) (Join-Path $windowsDir ("app_icon_{0}.png" -f $size))
}
$roundedMaster.Dispose()
$icoSizes = @(16, 24, 32, 48, 64, 128, 256)
$icoPaths = @()
foreach ($size in $icoSizes) { $icoPaths += (Join-Path $windowsDir ("app_icon_{0}.png" -f $size)) }
[MiguIcons]::WriteIco((Join-Path $windowsDir 'app_icon.ico'), $icoPaths)
Write-Output 'saved app_icon.ico'

# Android: flat legacy icons keep the full plate; adaptive layers are split.
$legacySizes = @{ 48 = 'mdpi'; 72 = 'hdpi'; 96 = 'xhdpi'; 144 = 'xxhdpi'; 192 = 'xxxhdpi' }
foreach ($size in $legacySizes.Keys) {
    Save-Bitmap ([MiguIcons]::Resize($master, $size)) (Join-Path $legacyDir ("ic_launcher_{0}.png" -f $size))
}

$adaptiveSizes = @{ 108 = 'mdpi'; 162 = 'hdpi'; 216 = 'xhdpi'; 324 = 'xxhdpi'; 432 = 'xxxhdpi' }
foreach ($size in $adaptiveSizes.Keys) {
    Save-Bitmap ([MiguIcons]::Gradient($size)) (Join-Path $bgDir ("ic_launcher_background_{0}.png" -f $size))
}
foreach ($size in $adaptiveSizes.Keys) {
    Save-Bitmap ([MiguIcons]::Foreground($master, $size, 0.86)) (Join-Path $fgDir ("ic_launcher_foreground_{0}.png" -f $size))
}

Save-Bitmap ([MiguIcons]::Resize($master, 512)) (Join-Path $androidDir 'play_store_icon_512.png')
$master.Dispose()

$resRoot = Join-Path $root 'android\app\src\main\res'
foreach ($size in $legacySizes.Keys) {
    Copy-Item (Join-Path $legacyDir ("ic_launcher_{0}.png" -f $size)) (Join-Path $resRoot ("mipmap-{0}\ic_launcher.png" -f $legacySizes[$size])) -Force
}
foreach ($size in $adaptiveSizes.Keys) {
    $density = $adaptiveSizes[$size]
    Copy-Item (Join-Path $bgDir ("ic_launcher_background_{0}.png" -f $size)) (Join-Path $resRoot ("mipmap-{0}\ic_launcher_background.png" -f $density)) -Force
    Copy-Item (Join-Path $fgDir ("ic_launcher_foreground_{0}.png" -f $size)) (Join-Path $resRoot ("mipmap-{0}\ic_launcher_foreground.png" -f $density)) -Force
}
Copy-Item (Join-Path $windowsDir 'app_icon.ico') (Join-Path $root 'windows\runner\resources\app_icon.ico') -Force
Write-Output 'platform resources updated'
