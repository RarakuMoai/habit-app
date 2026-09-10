#!/usr/bin/env python3
"""Run the native Flutter review and preserve PNGs before test app cleanup.

Uses only an explicitly named, booted CoreSimulator. The fixture lives in memory;
no phone, real app data, credentials, or external services are used.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--test', default='integration_test/experience_review_test.dart')
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
    booted = {d['udid'] for group in devices['devices'].values() for d in group}
    if args.device not in booted:
        parser.error('--device must identify an already booted iOS simulator')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    command = ['flutter', 'test', args.test, '--no-pub', '--flavor', 'dev', '-d', args.device,
               '--dart-define=APP_LOCALE=zh', '--dart-define=SCENE_HOUR=10']
    captured = []
    with (output / 'flutter.log').open('w') as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in process.stdout:
            log.write(line)
            log.flush()
            if 'REVIEW_SCREENSHOT ' in line:
                source = Path(line.split('REVIEW_SCREENSHOT ', 1)[1].strip())
                destination = output / source.name
                shutil.copy2(source, destination)
                if destination.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                    raise ValueError(f'Not a PNG: {destination}')
                captured.append(destination.name)
                print(f'Saved {destination.name}', flush=True)
            elif 'Exception' in line or 'Error:' in line or 'All tests passed' in line:
                print(line.rstrip(), flush=True)
        result = process.wait()
    (output / 'capture.json').write_text(json.dumps({'device': args.device, 'test': args.test,
        'files': captured, 'exit_code': result}, indent=2))
    return result

if __name__ == '__main__':
    sys.exit(main())
