#!/usr/bin/env python3
"""Mint an Apple Music developer token (JWT) for Sapphire's MusicKit integration.

Usage:
    ./scripts/make-musickit-token.py <MediaID> <KeyID> <AuthKey_<KeyID>.p8> [days]

  MediaID  Apple requires the MusicKit Media ID (not the plain app/team ID) as the
           JWT issuer. It looks like <TeamID>.media.<BundleID>, e.g.
           KVQFWJ7C7S.media.com.shariq.sapphire
  KeyID    the Apple Music API key ID (e.g. K9X8W7V6U5)
  .p8      the private key file downloaded from the developer portal
  days     token lifetime in days (default 180)

Requires only python3 + openssl (both ship with macOS / Xcode CLT).

Give the printed JWT to Sapphire via (priority order):
  export MUSICKIT_DEVELOPER_TOKEN="<token>"; open -a Sapphire
  ~/.sapphire/MusicKitConfig.plist  -> key "DeveloperToken"
  WeatherAPIKey.musicKitDeveloperToken (rebuild required)

Personalized Apple Music features (love, play counts, recently played, For You,
heavy rotation, library) additionally need a *user* token. Sapphire resolves it
from (priority): MUSICKIT_USER_TOKEN env var, ~/.sapphire/MusicKitConfig.plist
key "UserToken", the keychain, then MusicKit's DefaultMusicTokenProvider.
"""

import base64
import subprocess
import sys
import time

JWT_ALG = "ES256"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_integer(der: bytes, pos: int):
    """Parse a DER INTEGER at pos; returns (value, next_pos)."""
    assert der[pos] == 0x02, "expected INTEGER tag"
    length = der[pos + 1]
    off = pos + 2
    if length & 0x80:  # long form
        n = length & 0x7F
        length = int.from_bytes(der[off:off + n], "big")
        off += n
    raw = der[off:off + length]
    return int.from_bytes(raw, "big"), off + length


def skip_sequence_header(der: bytes):
    """DER signature is SEQUENCE { INTEGER r, INTEGER s }. Skip the SEQUENCE tag
    (0x30) and its length to land on the first INTEGER."""
    assert der[0] == 0x30, "expected SEQUENCE tag"
    length = der[1]
    pos = 2
    if length & 0x80:  # long form
        n = length & 0x7F
        length = int.from_bytes(der[pos:pos + n], "big")
        pos += n
    return pos


def main() -> None:
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    media_id, key_id, p8_path = sys.argv[1], sys.argv[2], sys.argv[3]
    days = int(sys.argv[4]) if len(sys.argv) > 4 else 180

    now = int(time.time())
    header = {"alg": JWT_ALG, "kid": key_id}
    # Apple keys the MusicKit media identifier (e.g. <TeamID>.media.<BundleID>),
    # not the plain app/team ID, in the `iss` claim.
    payload = {"iss": media_id, "iat": now, "exp": now + days * 86400}

    signing_input = (
        b64url(json_bytes(header)) + "." + b64url(json_bytes(payload))
    ).encode("ascii")

    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", p8_path],
        input=signing_input,
        capture_output=True,
        check=True,
    ).stdout

    r, pos = der_integer(der, skip_sequence_header(der))
    s, _ = der_integer(der, pos)

    def fixed32(value: int) -> bytes:
        return value.to_bytes(32, "big")

    signature = fixed32(r) + fixed32(s)
    token = signing_input.decode("ascii") + "." + b64url(signature)
    print(token)


def json_bytes(obj: dict) -> bytes:
    import json

    return json.dumps(obj, separators=(",", ":")).encode("ascii")


if __name__ == "__main__":
    main()
