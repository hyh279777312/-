import os
from PIL import Image, ImageDraw

img = Image.new('RGB', (300, 300), color='white')
draw = ImageDraw.Draw(img)

# Outer border
draw.rectangle([20, 20, 280, 280], outline='black', width=6)

# Finder patterns (corners)
def draw_finder(x, y):
    draw.rectangle([x, y, x+50, y+50], fill='black')
    draw.rectangle([x+10, y+10, x+40, y+40], fill='white')
    draw.rectangle([x+20, y+20, x+30, y+30], fill='black')

draw_finder(35, 35)
draw_finder(215, 35)
draw_finder(35, 215)

# Decorative dots simulating QR data
import random
random.seed(42)
for x in range(95, 205, 12):
    for y in range(35, 265, 12):
        if random.choice([True, False]):
            draw.rectangle([x, y, x+8, y+8], fill='black')

for x in range(35, 205, 12):
    for y in range(95, 205, 12):
        if random.choice([True, False]):
            draw.rectangle([x, y, x+8, y+8], fill='black')

# Center badge (Glassmorphic look)
draw.rounded_rectangle([115, 115, 185, 185], radius=12, fill='#0284c7', outline='white', width=3)

os.makedirs('public', exist_ok=True)
img.save('public/qrcode.png')
print("QR code generated at public/qrcode.png")
