using System.Buffers.Binary;

namespace KarimEldamatyWindows;

internal static class LocalPng
{
    public static void Validate(byte[] png)
    {
        ArgumentNullException.ThrowIfNull(png);
        if(png.Length is < 33 or > 10000000 || !png.AsSpan(0,8).SequenceEqual(new byte[]{137,80,78,71,13,10,26,10}) || BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(8,4))!=13 || !png.AsSpan(12,4).SequenceEqual("IHDR"u8)) throw new ArgumentException("Use a valid PNG smaller than 10 MB.");
        var width=BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(16,4));var height=BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(20,4));
        if(width is 0 or >4096 || height is 0 or >4096 || (long)width*height>16000000)throw new ArgumentException("Use a PNG up to 4,096 pixels per side and 16 million pixels.");
    }
}
