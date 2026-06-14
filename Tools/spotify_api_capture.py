"""
mitmproxy addon to capture Spotify web API requests.

Usage:
  1. Install mitmproxy:  brew install mitmproxy
  2. Trust the mitmproxy CA certificate (open http://mitm.it in browser)
  3. Configure your browser to use proxy localhost:8080
  4. Run:  mitmproxy -p 8080 -s spotify_api_capture.py
  5. Open Spotify web player and perform actions
  6. Stop mitmproxy (Ctrl+C) and check spotify_api_log.jsonl
"""

import json
import time
from urllib.parse import urlparse

SPOTIFY_DOMAINS = (
    "api.spotify.com",
    "spotify.com",
    "open.spotify.com",
    "spclient.wg.spotify.com",
    "gew1-spclient.spotify.com",
    "audio-ak-spotify-com.akamaized.net",
)

EXCLUDE_PATTERNS = (
    "/_auth/",
    "token",
    "google-analytics",
    "analytics",
    "doubleclick",
    "cdn",
    "chunk",
    "woff",
    "png",
    "jpg",
    "svg",
    "css",
    "js?",
)

log_file = open("spotify_api_log.jsonl", "w", buffering=1)


def is_relevant(flow):
    host = flow.request.pretty_host
    url = flow.request.pretty_url
    if not any(d in host for d in SPOTIFY_DOMAINS):
        return False
    if any(p in url for p in EXCLUDE_PATTERNS):
        return False
    return True


def request(flow):
    if not is_relevant(flow):
        return

    entry = {
        "timestamp": time.time(),
        "method": flow.request.method,
        "url": flow.request.pretty_url,
        "host": flow.request.pretty_host,
        "path": urlparse(flow.request.pretty_url).path,
        "headers": dict(flow.request.headers),
        "body": flow.request.get_text(strict=False),
    }

    print(f"[SpotifyAPI] {flow.request.method} {entry['path']}")
    log_file.write(json.dumps(entry) + "\n")


def response(flow):
    if not is_relevant(flow):
        return

    status = flow.response.status_code
    content_type = flow.response.headers.get("content-type", "")
    body_len = len(flow.response.get_text(strict=False) or "")

    if "json" in content_type or status >= 400:
        body = flow.response.get_text(strict=False)
        print(f"[SpotifyAPI]   -> {status} ({body_len}B) {body[:200] if body else ''}")
    else:
        print(f"[SpotifyAPI]   -> {status} ({body_len}B)")
