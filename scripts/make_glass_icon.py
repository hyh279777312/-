import struct, zlib, math

def make_glass_icon(filename="public/icon.png"):
    width, height = 512, 512
    pixels = bytearray(width * height * 3)

    # Center and radius for rounded glass card
    cx, cy = 256, 256
    card_x0, card_y0, card_x1, card_y1 = 64, 64, 448, 448
    corner_radius = 64

    for y in range(height):
        for x in range(width):
            idx = (y * width + x) * 3

            # 1. Background gradient (dark midnight blue to deep purple)
            fx = x / width
            fy = y / height
            
            # Base dark gradient
            r = int(11 + fx * 30 + fy * 20)
            g = int(15 + fx * 20 + fy * 40)
            b = int(25 + fx * 50 + fy * 80)

            # Add subtle ambient glowing orbs in background
            # Orb 1 (Cyan top-left)
            d1 = math.sqrt((x - 150)**2 + (y - 150)**2)
            if d1 < 180:
                factor = (1 - d1 / 180) * 0.35
                r = int(r + factor * 20)
                g = int(g + factor * 180)
                b = int(b + factor * 220)

            # Orb 2 (Magenta bottom-right)
            d2 = math.sqrt((x - 360)**2 + (y - 360)**2)
            if d2 < 200:
                factor = (1 - d2 / 200) * 0.3
                r = int(r + factor * 200)
                g = int(g + factor * 40)
                b = int(b + factor * 180)

            # 2. Glass Card with Rounded Corners & Frosted Border
            in_card = False
            # Check rounded box
            # Distance to center of rounded rect inner region
            rx = max(card_x0 + corner_radius, min(x, card_x1 - corner_radius))
            ry = max(card_y0 + corner_radius, min(y, card_y1 - corner_radius))
            dist = math.sqrt((x - rx)**2 + (y - ry)**2)

            if x >= card_x0 and x <= card_x1 and y >= card_y0 and y <= card_y1:
                # Check corners
                is_corner = False
                if x < card_x0 + corner_radius and y < card_y0 + corner_radius:
                    if math.sqrt((x - (card_x0 + corner_radius))**2 + (y - (card_y0 + corner_radius))**2) > corner_radius:
                        is_corner = True
                elif x > card_x1 - corner_radius and y < card_y0 + corner_radius:
                    if math.sqrt((x - (card_x1 - corner_radius))**2 + (y - (card_y0 + corner_radius))**2) > corner_radius:
                        is_corner = True
                elif x < card_x0 + corner_radius and y > card_y1 - corner_radius:
                    if math.sqrt((x - (card_x0 + corner_radius))**2 + (y - (card_y1 - corner_radius))**2) > corner_radius:
                        is_corner = True
                elif x > card_x1 - corner_radius and y > card_y1 - corner_radius:
                    if math.sqrt((x - (card_x1 - corner_radius))**2 + (y - (card_y1 - corner_radius))**2) > corner_radius:
                        is_corner = True

                if not is_corner:
                    in_card = True

            if in_card:
                # Glass frosted overlay blending
                # Glass gradient (diagonal sheen)
                glass_mix = ((x + y) / (width + height)) * 0.25
                
                # Blend with semi-transparent white/cyan glass tint
                r = int(r * 0.4 + (255 * 0.25 + glass_mix * 50))
                g = int(g * 0.4 + (255 * 0.30 + glass_mix * 80))
                b = int(b * 0.4 + (255 * 0.45 + glass_mix * 120))

                # Glass border highlight (top & left edge)
                edge_dist = min(x - card_x0, card_x1 - x, y - card_y0, card_y1 - y)
                if edge_dist < 4:
                    # Highlight border
                    r = min(255, r + 120)
                    g = min(255, g + 140)
                    b = min(255, b + 180)

                # 3. Inner Symbol: Central Play / Video Box & Sparkle / HQS emblem
                # Let's draw a glowing play triangle and intersecting rings in the center
                dx = x - cx
                dy = y - cy
                dist_center = math.sqrt(dx**2 + dy**2)

                # Inner glowing circle badge
                if dist_center < 75:
                    ring_factor = 1 - (dist_center / 75)
                    r = int(r * 0.3 + 14 * ring_factor * 20)
                    g = int(g * 0.3 + 165 * ring_factor * 1.5)
                    b = int(b * 0.3 + 233 * ring_factor * 1.5)
                
                # Play triangle shape inside center
                # Triangle vertices: (230, 215), (230, 297), (305, 256)
                if x >= 225 and x <= 315 and y >= 210 and y <= 302:
                    # check triangle math
                    # barycentric or half-plane tests for triangle (x1,y1)=(230,215), (x2,y2)=(230,297), (x3,y3)=(305,256)
                    x1, y1 = 232, 218
                    x2, y2 = 232, 294
                    x3, y3 = 302, 256
                    
                    def sign(p1x, p1y, p2x, p2y, p3x, p3y):
                        return (p1x - p3x) * (p2y - p3y) - (p2x - p3x) * (p1y - p3y)
                    
                    s1 = sign(x, y, x1, y1, x2, y2) < 0
                    s2 = sign(x, y, x2, y2, x3, y3) < 0
                    s3 = sign(x, y, x3, y3, x1, y1) < 0
                    
                    if (s1 == s2) and (s2 == s3):
                        # Inside play triangle - pure bright white / cyan glowing fill
                        r = 255
                        g = 255
                        b = 255

            pixels[idx] = max(0, min(255, r))
            pixels[idx+1] = max(0, min(255, g))
            pixels[idx+2] = max(0, min(255, b))

    # Encode to PNG
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr_chunk = b'IHDR' + ihdr_data
    ihdr_crc = struct.pack('>I', zlib.crc32(ihdr_chunk) & 0xFFFFFFFF)
    ihdr = struct.pack('>I', len(ihdr_data)) + ihdr_chunk + ihdr_crc

    # Scanline filtering (filter type 0 for each row)
    row_stride = width * 3
    filtered_data = bytearray()
    for y in range(height):
        filtered_data.append(0) # filter type none
        start = y * row_stride
        filtered_data.extend(pixels[start:start+row_stride])

    compressed = zlib.compress(filtered_data, level=9)
    idat_chunk = b'IDAT' + compressed
    idat_crc = struct.pack('>I', zlib.crc32(idat_chunk) & 0xFFFFFFFF)
    idat = struct.pack('>I', len(compressed)) + idat_chunk + idat_crc

    iend_chunk = b'IEND'
    iend_crc = struct.pack('>I', zlib.crc32(iend_chunk) & 0xFFFFFFFF)
    iend = struct.pack('>I', 0) + iend_chunk + iend_crc

    png_bytes = sig + ihdr + idat + iend

    import os
    os.makedirs('public', exist_ok=True)
    with open(filename, 'wb') as f:
        f.write(png_bytes)
    print(f"Glassmorphic icon successfully generated at {filename}")

if __name__ == '__main__':
    make_glass_icon()
