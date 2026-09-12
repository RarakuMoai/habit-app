#!/usr/bin/env python3
"""Decode sampled frames from real recordings and make labeled review sheets.

Requires the compiled extract_entry_video_frames.swift executable and Pillow.
Original PNGs and MP4s remain unchanged. This is playback validation, not an
FPS, audio, physical-device or native cold-launch performance measurement.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--decoder', type=Path, required=True)
    parser.add_argument('captures', nargs='+', type=Path)
    args = parser.parse_args()
    for directory in args.captures:
        capture_file = directory / 'capture.json'
        capture = json.loads(capture_file.read_text())
        passed = capture.get('test_exit_code') == 0 or capture.get('manual_review_complete') is True
        if not passed or capture['errors']:
            raise ValueError('Capture did not pass: ' + str(directory))
        video = directory / capture['video']['file']
        result = subprocess.run([str(args.decoder), str(video), str(directory / 'decoded')], check=True, text=True, capture_output=True)
        lines = result.stdout.splitlines()
        samples = [line for line in lines if line.startswith('frame-')]
        if len(samples) < 4:
            raise ValueError('Decoder did not provide four samples')
        capture['video'].update({
            'decoded': True,
            'decodeMethod': 'AVFoundation exact-time image generation; four sampled frames',
            'durationSeconds': float(re.search(r'duration_seconds=(\S+)', result.stdout)[1]),
            'audioTracks': int(re.search(r'audio_tracks=(\d+)', result.stdout)[1]),
            'sha256': hashlib.sha256(video.read_bytes()).hexdigest(),
            'decodedFrames': samples,
        })
        (directory / 'video-decode.log').write_text(result.stdout + result.stderr)
        capture_file.write_text(json.dumps(capture, ensure_ascii=False, indent=2) + '\n')
        images = list(directory.glob('*.png')) + sorted((directory / 'decoded').glob('*.png'))
        width, height, columns = 250, 560, 4
        sheet = Image.new('RGB', (width * columns, height * ((len(images) + columns - 1) // columns)), '#eeeae1')
        draw = ImageDraw.Draw(sheet)
        for index, path in enumerate(images):
            x, y = (index % columns) * width, (index // columns) * height
            with Image.open(path) as im:
                im.load()
                im.thumbnail((width - 12, height - 36))
                sheet.paste(im.convert('RGB'), (x + (width - im.width) // 2, y + 28))
            draw.text((x + 6, y + 7), path.stem, fill='#30392e')
        sheet.save(directory / 'review-contact.jpg', quality=92)
        print(str(directory) + ': ' + str(capture['video']['durationSeconds']) + ' s; 4 decoded samples; ' + str(len(images)) + ' review frames')


if __name__ == '__main__':
    main()
