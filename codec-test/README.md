# Codec test

`CodecTest.cs` calls the same `System.Drawing.Image.FromFile(path, useEmbeddedColorManagement)` overload
eApp's form viewer uses, on every file in a folder, with and without embedded colour management, and
reports which decode. It is how the Deflate-TIFF failure was found and how the WIC fix was proven.

Build inside a prefix that has .NET 4.8:

    wine 'C:\windows\Microsoft.NET\Framework\v4.0.30319\csc.exe' /nologo /platform:x86 /out:C:\codec\CodecTest.exe /r:System.Drawing.dll C:\codec\CodecTest.cs
    wine 'C:\codec\CodecTest.exe' 'C:\codec'

Test images are generated with `sips`, `tiffutil`, and ImageMagick; see the session notes. AIL's real
form pages are 1-bit Group 4 (most), Deflate (about 1 in 10, including every `_R23`/`_R24` revision),
and LZW (a few). Wine's own decoder fails the Deflate ones; Microsoft's WIC reads all of them.
