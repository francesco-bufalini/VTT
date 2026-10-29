"""Crop rendered silhouettes and composite the calibrated 1.50 m grid backdrop.

Render first with render_character_portraits.gd, using the curated portrait spec.
The source PCKs and their calibrated transforms remain unchanged.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]


def compose(render_dir, output_dir):
    spec = json.loads((ROOT / 'scripts/data/character_miniature_portraits.json').read_text())
    metrics = json.loads((render_dir / 'render_metrics.json').read_text())
    assert {p['id'] for p in spec['tokens']} == {p['id'] for p in metrics}
    output_dir.mkdir(parents=True, exist_ok=True)
    for record in metrics:
        source = Image.open(render_dir / (record['id'] + '.png')).convert('RGBA')
        alpha = source.getchannel('A')
        box = alpha.getbbox()
        assert box and min(box[:2]) > 0 and box[2] < source.width and box[3] < source.height, record['id']
        margin = spec['margin_pixels']
        left, top, right, bottom = box
        crop = source.crop(box)
        size = (crop.width + 2 * margin, crop.height + 2 * margin)
        background = Image.new('RGBA', size, tuple(spec['background_rgb']) + (255,))
        draw = ImageDraw.Draw(background)
        step = record['pixels_per_cell']
        ground = record['ground_pixel'] - top + margin
        center_x = source.width / 2 - left + margin
        for index in range(-8, 9):
            y = round(ground - index * step)
            x = round(center_x + index * step)
            draw.line([(0, y), (size[0], y)], fill=(77, 89, 107), width=2)
            draw.line([(x, 0), (x, size[1])], fill=(77, 89, 107), width=2)
        background.alpha_composite(crop, (margin, margin))
        background.convert('RGB').save(output_dir / (record['id'] + '.webp'), quality=92, method=6)
        print(record['id'], size)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'pwa/miniature-images')
    args = parser.parse_args()
    compose(args.render_dir, args.output_dir)
