import json
import pathlib
import plistlib
import selectors
import subprocess
import sys
import tempfile
import time


class Client:
    def __init__(self, executable, output):
        self.process = subprocess.Popen(
            [str(executable), "--mcp", "-settings.ffmpeg.path", "/opt/homebrew/bin/ffmpeg",
             "-settings.output.directory", str(output)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.sequence = 0
        self.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                    "clientInfo": {"name": "pipeline-lock-test", "version": "1"}})
        self.process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        self.process.stdin.flush()

    def request(self, method, params):
        self.sequence += 1
        self.process.stdin.write((json.dumps({"jsonrpc": "2.0", "id": self.sequence,
                                             "method": method, "params": params}) + "\n").encode())
        self.process.stdin.flush()
        assert self.selector.select(10), "MCP response timeout"
        reply = json.loads(self.process.stdout.readline())
        assert reply["id"] == self.sequence
        return reply["result"]

    def call(self, name, arguments):
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        return result, json.loads(result["content"][0]["text"])

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            self.process.wait(timeout=15)
        self.selector.close()


def check(app):
    executable = app / "Contents/MacOS" / plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleExecutable"]
    with tempfile.TemporaryDirectory(prefix="linkdeck-lock-") as temporary:
        root = pathlib.Path(temporary)
        output = root / "output"
        output.mkdir()
        media = root / "audio.wav"
        subprocess.run(["/opt/homebrew/bin/ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                        "sine=duration=30", str(media)], check=True)
        subtitle = root / "ko.srt"
        subtitle.write_text("1\n00:00:00,000 --> 00:00:30,000\n한국어 자막 테스트\n", encoding="utf-8")
        clients = [Client(executable, output), Client(executable, output)]
        args = {"media_path": str(media), "subtitle_path": str(subtitle), "output_name": "pipeline"}
        try:
            response, first = clients[0].call("burn_subtitles", args)
            assert not response.get("isError"), first
            response, rejected = clients[1].call("burn_subtitles", args)
            assert response.get("isError"), "Two API processes started rendering simultaneously"
            clients[0].call("cancel_subtitle_render", {"job_id": first["job_id"]})
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                _, state = clients[0].call("get_subtitle_status", {"job_id": first["job_id"]})
                if state["phase"] in ("completed", "failed", "canceled"):
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("Cancellation never settled")
            response, second = clients[1].call("burn_subtitles", args)
            assert not response.get("isError"), second
            clients[1].process.terminate()
            assert clients[1].process.wait(timeout=15) == 0
            assert not list(output.glob(".linkdeck-*")), "SIGTERM left temporary render work"
            assert media.exists() and subtitle.exists()
            print("PASS: cross-process exclusion, cancel releases slot, SIGTERM cleanup, inputs preserved")
        finally:
            for client in clients:
                client.close()


if __name__ == "__main__":
    check(pathlib.Path(sys.argv[1]).resolve())
