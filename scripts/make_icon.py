import struct, zlib
import os

def make_png(width, height, rgb_color=(15, 23, 42)):
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr_chunk = b'IHDR' + ihdr_data
    ihdr_crc = struct.pack('>I', zlib.crc32(ihdr_chunk) & 0xFFFFFFFF)
    ihdr = struct.pack('>I', len(ihdr_data)) + ihdr_chunk + ihdr_crc

    row = b'\x00' + bytes(rgb_color) * width
    raw_data = row * height
    compressed = zlib.compress(raw_data)
    idat_chunk = b'IDAT' + compressed
    idat_crc = struct.pack('>I', zlib.crc32(idat_chunk) & 0xFFFFFFFF)
    idat = struct.pack('>I', len(compressed)) + idat_chunk + idat_crc

    iend_chunk = b'IEND'
    iend_crc = struct.pack('>I', zlib.crc32(iend_chunk) & 0xFFFFFFFF)
    iend = struct.pack('>I', 0) + iend_chunk + iend_crc

    return sig + ihdr + idat + iend

os.makedirs('build', exist_ok=True)
with open('build/icon.png', 'wb') as f:
    f.write(make_png(512, 512, (15, 23, 42)))
print('Icon generated successfully')
