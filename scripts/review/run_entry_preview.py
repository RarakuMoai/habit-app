#!/usr/bin/env python3
"""Capture only a named, booted iOS simulator running the isolated debug target."""
import argparse
import hashlib
import json
from pathlib import Path
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--device', required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
booted = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
assert a.device in {d['udid'] for group in booted['devices'].values() for d in group}, 'Use a booted simulator UUID'
a.output.mkdir(parents=True, exist_ok=True)
command = ['/Users/raraku/development/flutter/bin/flutter', 'test', 'integration_test/entry_cover_review_test.dart', '--no-pub', '--flavor', 'dev', '-d', a.device]
recording = None
captures = []
with (a.output / 'flutter.log').open('w') as log:
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        for line in process.stdout:
            log.write(line); log.flush()
            if 'ENTRY_RECORD_START' in line:
                recording = subprocess.Popen(['xcrun', 'simctl', 'io', a.device, 'recordVideo', '--codec=h264', '--force', str(a.output / 'walkthrough.mp4')], stdout=log, stderr=log)
            elif 'ENTRY_CAPTURE ' in line:
                name, acknowledgment = line.split('ENTRY_CAPTURE ', 1)[1].strip().split(' ', 1)
                assert name.replace('-', '').isalnum()
                dest = a.output / (name + '.png')
                subprocess.run(['xcrun', 'simctl', 'io', a.device, 'screenshot', str(dest)], check=True, stdout=log, stderr=log)
                data = dest.read_bytes(); assert data.startswith(b'\x89PNG\r\n\x1a\n')
                captures.append({'file':dest.name, 'sha256':hashlib.sha256(data).hexdigest()})
                Path(acknowledgment).write_text('captured')
                print('Captured ' + name, flush=True)
            elif 'ENTRY_RECORD_STOP' in line and recording:
                recording.send_signal(signal.SIGINT); recording.wait(timeout=20); recording = None
            elif 'Error' in line or 'Exception' in line or 'All tests passed' in line:
                print(line.rstrip(), flush=True)
    finally:
        if recording:
            recording.send_signal(signal.SIGINT); recording.wait(timeout=20)
    code = process.wait()
repeated = [b['file'] for a,b in zip(captures, captures[1:]) if a['sha256'] == b['sha256']]
exit_code = code or int(len(captures) != 22 or bool(repeated))
(a.output / 'capture.json').write_text(json.dumps({'device':a.device,'command':command,'captures':captures,'repeated':repeated,'test_exit_code':code,'exit_code':exit_code},indent=2))
raise SystemExit(exit_code)
