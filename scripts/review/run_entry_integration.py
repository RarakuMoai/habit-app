#!/usr/bin/env python3
"""Native captures of the real Flutter root with integration-only state fixtures.

Requires an explicitly named, already booted, dedicated iOS test simulator.
This host script never issues erase/uninstall commands or changes bundle IDs.
Flutter test manages its own installation and can remove that test installation
afterward; never use a simulator holding a normal app verification session.
Screenshots remain unedited; fixture/source provenance is stored in capture.json.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='Booted iOS simulator UUID')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--before', action='store_true')
    parser.add_argument('--scenario', choices=['first', 'returningGuest', 'returningSignedIn', 'authErrors', 'appleNew', 'googleRestore', 'credentialsOffline', 'initFailure', 'background'], default='first')
    parser.add_argument('--skip-meeting', action='store_true')
    parser.add_argument('--large-text', action='store_true', help='Inject Flutter test textScale 2.0; manifest records actual app clamp')
    parser.add_argument('--reduce-motion', action='store_true', help='Inject Flutter test reduceMotion and disableAnimations; does not change OS settings')
    parser.add_argument('--flutter', default=os.environ.get('FLUTTER_BIN') or shutil.which('flutter') or '/Users/raraku/development/flutter/bin/flutter')
    parser.add_argument('--dart-define', action='append', default=[])
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
    matches = [(runtime, device) for runtime, group in devices['devices'].items() for device in group if device['udid'] == args.device and device['state'] == 'Booted']
    if len(matches) != 1 or 'iOS' not in matches[0][0]:
        parser.error('--device must be an explicitly named, already booted iOS simulator UUID')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error('--output must be empty; previous review evidence will not be overwritten')
    command = [args.flutter, 'test', 'integration_test/entry_integration_review_test.dart', '--no-pub', '--flavor', 'redesign', '-d', args.device, '--timeout', '8m', f'--dart-define=ENTRY_REVIEW_BEFORE={str(args.before).lower()}', f'--dart-define=ENTRY_REVIEW_SCENARIO={args.scenario}', f'--dart-define=ENTRY_REVIEW_SKIP_MEETING={str(args.skip_meeting).lower()}', f'--dart-define=ENTRY_REVIEW_LARGE_TEXT={str(args.large_text).lower()}', f'--dart-define=ENTRY_REVIEW_REDUCE_MOTION={str(args.reduce_motion).lower()}']
    command.extend('--dart-define=' + value for value in args.dart_define)
    # Git diff excludes new runtime assets and Dart files. Hash both tracked
    # and untracked working sources so each recording identifies its exact tree.
    source_paths = subprocess.check_output([
        'git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z',
        '--', 'lib', 'assets', 'ios/Runner', 'pubspec.yaml', 'pubspec.lock',
        'integration_test/entry_integration_review_test.dart',
        'scripts/review/run_entry_integration.py',
    ], cwd=ROOT).split(b'\0')
    source_hashes = {}
    for raw in source_paths:
        if not raw:
            continue
        relative = os.fsdecode(raw)
        source_file = ROOT / relative
        if source_file.is_file():
            source_hashes[relative] = hashlib.sha256(source_file.read_bytes()).hexdigest()
    provenance = {
        'branch': subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip(),
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'status': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True).splitlines(),
        'diff_sha256': hashlib.sha256(subprocess.check_output(['git', 'diff'], cwd=ROOT)).hexdigest(),
        'source_files_sha256': source_hashes,
        'source_tree_sha256': hashlib.sha256(json.dumps(source_hashes, sort_keys=True).encode()).hexdigest(),
    }
    recording = None
    captures, frames, errors = [], [], []
    metadata = {}
    lifecycle = []
    background = []
    expected_count = None

    def acknowledge(name, path):
        ack = Path(path)
        if not re.fullmatch(r'[A-Za-z0-9-]+', name) or ack.name != name + '.ready' or not ack.parent.name.startswith('entry-integration-review-') or not ack.is_absolute():
            raise ValueError('Unexpected capture handshake path: ' + path)
        ack.write_text('captured', encoding='utf-8')

    def stop_recording():
        nonlocal recording
        if recording is not None:
            recording.send_signal(signal.SIGINT)
            code = recording.wait(timeout=20)
            if code:
                errors.append(f'simctl recordVideo exited {code}')
            recording = None

    with (output / 'flutter.log').open('w', encoding='utf-8') as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if 'ENTRY_RECORD_START ' in line:
                    name, ack = line.split('ENTRY_RECORD_START ', 1)[1].strip().split(' ', 1)
                    if recording:
                        raise RuntimeError('A video is already recording')
                    recording = subprocess.Popen(['xcrun', 'simctl', 'io', args.device, 'recordVideo', '--codec=h264', '--force', str(output / 'walkthrough.mp4')], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                    # simctl emits this after it has attached to the framebuffer.
                    # ACK only then allows app.main and the first transition.
                    for ready in recording.stdout:
                        log.write(ready)
                        log.flush()
                        if 'Recording started' in ready:
                            break
                    else:
                        raise RuntimeError('simctl did not start recording')
                    acknowledge(name, ack)
                elif 'ENTRY_CAPTURE ' in line:
                    name, ack = line.split('ENTRY_CAPTURE ', 1)[1].strip().split(' ', 1)
                    if not re.fullmatch(r'[A-Za-z0-9-]+', name):
                        raise ValueError('Invalid capture name')
                    dest = output / (name + '.png')
                    subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot', str(dest)], check=True, stdout=log, stderr=log)
                    data = dest.read_bytes()
                    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
                        raise ValueError('simctl did not produce a PNG')
                    captures.append({'file': dest.name, 'sha256': hashlib.sha256(data).hexdigest()})
                    acknowledge(name, ack)
                    print('Captured ' + name, flush=True)
                elif 'ENTRY_BACKGROUND_REQUEST ' in line:
                    name, ack = line.split('ENTRY_BACKGROUND_REQUEST ', 1)[1].strip().split(' ', 1)
                    commands = [
                        ['xcrun', 'simctl', 'launch', args.device, 'com.apple.Preferences'],
                        ['xcrun', 'simctl', 'launch', args.device, 'com.yayoi991331.habitapp.redesign'],
                    ]
                    started = time.monotonic()
                    for index, native_command in enumerate(commands):
                        result = subprocess.run(native_command, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                        log.write(result.stdout)
                        background.append({'command': native_command, 'output': result.stdout.strip()})
                        if index == 0:
                            time.sleep(2)
                    background.append({'elapsedSeconds': time.monotonic() - started, 'terminatedApp': False})
                    acknowledge(name, ack)
                elif 'ENTRY_REVIEW_LIFECYCLE ' in line:
                    lifecycle = json.loads(line.split('ENTRY_REVIEW_LIFECYCLE ', 1)[1])
                elif 'ENTRY_REVIEW_META ' in line:
                    metadata = json.loads(line.split('ENTRY_REVIEW_META ', 1)[1])
                elif 'ENTRY_REVIEW_FRAME ' in line:
                    frames.append(json.loads(line.split('ENTRY_REVIEW_FRAME ', 1)[1]))
                elif 'ENTRY_REVIEW_COMPLETE ' in line:
                    expected_count = int(line.split('ENTRY_REVIEW_COMPLETE ', 1)[1])
                elif 'ENTRY_RECORD_STOP' in line:
                    stop_recording()
                elif any(marker in line for marker in ['Error', 'Exception', 'All tests passed', 'failed', 'Xcode build done']):
                    print(line.rstrip(), flush=True)
        except BaseException as error:
            errors.append(str(error))
            process.terminate()
        finally:
            stop_recording()
        code = process.wait()
    video = output / 'walkthrough.mp4'
    if expected_count is None or expected_count != len(captures):
        errors.append(f'Expected {expected_count} screenshots, captured {len(captures)}')
    if not video.exists() or video.stat().st_size == 0:
        errors.append('No nonempty continuous recording was produced')
    repeated = [second['file'] for first, second in zip(captures, captures[1:]) if first['sha256'] == second['sha256']]
    expected_identical = {'02b-login-cancelled.png', '02d-offline-login.png'} if args.scenario == 'authErrors' else set()
    unexpected_repeated = [name for name in repeated if name not in expected_identical]
    if unexpected_repeated:
        errors.append('Adjacent identical frames require review: ' + ', '.join(unexpected_repeated))
    result = {
        'device': matches[0][1], 'runtime': matches[0][0], 'source': provenance,
        'command': command, 'metadata': metadata, 'frames': frames, 'captures': captures,
        'native_background': background, 'observed_lifecycle': lifecycle,
        'adjacent_identical_frames': repeated, 'expected_unchanged_frames': sorted(expected_identical),
        'video': {'file': video.name, 'bytes': video.stat().st_size if video.exists() else 0, 'decoded': False},
        'test_exit_code': code, 'errors': errors,
        'notes': ['Video begins at the integration runner handshake before real app.main, not before iOS process launch.', 'Identity and preferences are test fixtures. The app root, scene, routes, audio services and timer are real code.', 'Account-provider outcomes and network failures are simulated in a test-only backend; device network is not changed.', 'Initialization failure is injected into the mock preference store and exercises the real root error/retry UI.', 'Accessibility flags, when requested, are Flutter test platformDispatcher values, not OS Settings operations.', 'Flutter test owns installation/cleanup and can remove its redesign test app after execution. Use a dedicated test simulator, not one preserving a normal app session.', 'No physical-device, OAuth, backup publication, notification permission or performance validation.'],
    }
    (output / 'capture.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    for error in errors:
        print(error, file=sys.stderr)
    return code or int(bool(errors))


if __name__ == '__main__':
    raise SystemExit(main())
