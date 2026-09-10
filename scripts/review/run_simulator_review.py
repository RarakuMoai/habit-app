#!/usr/bin/env python3
"""Run the native Flutter review and preserve PNGs before test app cleanup.

Uses only an explicitly named, booted CoreSimulator. The fixture lives in memory;
no phone, real app data, credentials, or external services are used.
"""
import argparse
import hashlib
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
    parser.add_argument('--glass', action='store_true', help='Capture the optional frosted navigation candidate')
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
    booted = {d['udid'] for group in devices['devices'].values() for d in group}
    if args.device not in booted:
        parser.error('--device must identify an already booted iOS simulator')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    command = ['flutter', 'test', args.test, '--no-pub', '--flavor', 'redesign', '-d', args.device,
               '--dart-define=APP_LOCALE=zh', '--dart-define=SCENE_HOUR=10',
               f'--dart-define=NAV_GLASS={str(args.glass).lower()}']
    captured = []
    fingerprints = []
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
                fingerprints.append(hashlib.sha256(destination.read_bytes()).hexdigest())
                print(f'Saved {destination.name}', flush=True)
            elif 'Exception' in line or 'Error:' in line or 'All tests passed' in line:
                print(line.rstrip(), flush=True)
        result = process.wait()
    # These review scripts advance to a different UI state for every capture.
    # iOS permission alerts can freeze the native surface while Flutter's test
    # tree keeps advancing; a passing test alone cannot validate those images.
    repeated = [captured[i] for i in range(1, len(captured))
                if fingerprints[i] == fingerprints[i - 1]]
    capture_error = ('Consecutive states produced identical PNGs; inspect the simulator for a system alert: '
                     + ', '.join(repeated)) if repeated else None
    if not captured:
        capture_error = 'No screenshots were captured.'
    if capture_error:
        print(capture_error, file=sys.stderr)
    exit_code = result or (1 if capture_error else 0)
    (output / 'capture.json').write_text(json.dumps({'device': args.device, 'test': args.test,
        'flavor': 'redesign', 'glass': args.glass, 'files': captured,
        'test_exit_code': result, 'capture_error': capture_error, 'exit_code': exit_code}, indent=2))
    return exit_code

if __name__ == '__main__':
    sys.exit(main())
