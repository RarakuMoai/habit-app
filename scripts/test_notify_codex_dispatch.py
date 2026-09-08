"""Offline tests only: never publish a real completion notification."""

import concurrent.futures
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

import notify_codex_dispatch as notifier
import setup_codex_phone_notify as setup


class NotificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name)
        self.config = {"topic": "test-only", "host": "https://example.invalid"}
        self.payload = json.dumps({
            "type": "agent-turn-complete", "thread-id": "thread", "turn-id": "turn",
            "last-assistant-message": "SECRET reply?", "input-messages": ["SECRET prompt"],
        })

    @patch.object(notifier, "publish", return_value=True)
    def test_only_identified_completion_events_send(self, publish):
        for payload in ["bad json", "[]", "null", "{}", '{"type":"SubagentStop"}',
                        '{"type":"agent-turn-complete"}']:
            notifier.notify_phone(self.config, payload, self.state)
        publish.assert_not_called()
        notifier.notify_phone(self.config, self.payload, self.state)
        publish.assert_called_once()

    @patch.object(notifier, "publish", return_value=True)
    def test_concurrent_duplicate_completions_send_once(self, publish):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            futures = [pool.submit(notifier.notify_phone, self.config, self.payload, self.state)
                       for _ in range(8)]
            for future in futures:
                future.result()
        publish.assert_called_once()

    @patch.object(notifier, "publish", side_effect=[False, True])
    def test_failed_delivery_does_not_prevent_later_retry(self, publish):
        notifier.notify_phone(self.config, self.payload, self.state)
        self.assertFalse(list(self.state.glob("*.sent")))
        notifier.notify_phone(self.config, self.payload, self.state)
        self.assertEqual(len(list(self.state.glob("*.sent"))), 1)

    @patch.object(notifier.urllib.request, "urlopen")
    def test_utf8_generic_message_never_includes_conversation(self, urlopen):
        urlopen.return_value.__enter__.return_value.status = 200
        notifier.notify_phone(self.config, self.payload, self.state)
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "https://example.invalid/")
        body = json.loads(request.data)
        self.assertEqual(body["topic"], "test-only")
        self.assertEqual(body["title"], "Codex 本輪已停止")
        self.assertNotIn("SECRET", request.data.decode())
        self.assertNotIn("thread", request.data.decode())

    @patch.object(notifier.time, "sleep")
    @patch.object(notifier.urllib.request, "urlopen")
    def test_transient_failure_retries_but_permanent_rejection_does_not(self, urlopen, sleep):
        response = MagicMock()
        response.__enter__.return_value.status = 200
        urlopen.side_effect = [urllib.error.URLError("offline"), response]
        self.assertTrue(notifier.publish(self.config, self.state))
        self.assertEqual(urlopen.call_count, 2)
        urlopen.reset_mock()
        urlopen.side_effect = urllib.error.HTTPError("", 403, "Forbidden", {}, None)
        self.assertFalse(notifier.publish(self.config, self.state))
        self.assertEqual(urlopen.call_count, 1)

    @patch.object(notifier.time, "sleep")
    @patch.object(notifier.urllib.request, "urlopen", side_effect=urllib.error.URLError("offline"))
    def test_failure_is_bounded_and_logged_without_payload(self, urlopen, sleep):
        self.assertFalse(notifier.publish(self.config, self.state))
        self.assertEqual(urlopen.call_count, 3)
        self.assertIn("unconfirmed", (self.state / "notify.log").read_text())

    @patch.object(notifier.subprocess, "run")
    def test_native_handler_receives_original_payload_as_one_argument(self, run):
        run.return_value.returncode = 0
        command = ["/path with spaces/helper", "turn-ended"]
        notifier.forward_native(command, self.payload, self.state)
        self.assertEqual(run.call_args.args[0], command + [self.payload])
        self.assertNotIn("shell", run.call_args.kwargs)

    def test_setup_preserves_settings_and_handler_and_is_repeatable(self):
        config = self.state / "config.toml"
        original_command = ["/path with spaces/helper", "turn-ended"]
        suffix = 'model = "gpt-6-astra"\n\n[desktop]\npreventSleepWhileRunning = true\n'
        original = "notify = " + json.dumps(original_command) + "\n" + suffix
        config.write_text(original)
        setup.install(self.state, "test-only")
        installed = config.read_text()
        settings_path = self.state / "phone-notify/settings.json"
        settings = json.loads(settings_path.read_text())
        self.assertEqual(settings["original_notify"], original_command)
        self.assertTrue(installed.endswith(suffix))
        setup.install(self.state, "test-only")
        self.assertEqual(config.read_text(), installed)
        self.assertEqual(json.loads(settings_path.read_text()), settings)
        backups = list(self.state.glob("config.toml.before-phone-notify-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)

    def test_setup_refuses_unsupported_config_without_writing(self):
        config = self.state / "config.toml"
        original = '[desktop]\nnotify = ["helper"]\n'
        config.write_text(original)
        with self.assertRaises(ValueError):
            setup.install(self.state, "test-only")
        self.assertEqual(config.read_text(), original)
        self.assertFalse((self.state / "phone-notify").exists())


if __name__ == "__main__":
    unittest.main()
