#!/bin/bash
#
# make_musickit_token.sh — mint an Apple Music developer token (JWT) and embed
# it, masked, into Sapphire's WeatherAPIKey.swift.
#
# The .p8 private key is used only HERE, at build/install time. It is never
# embedded in the app. What ships is the finished JWT, which Apple accepts for
# the configured lifetime (default 180 days) because it is signed by the key.
#
# Usage:
#   ./make_musickit_token.sh <MediaID> <KeyID> <AuthKey_<KeyID>.p8> [days] [WeatherAPIKey.swift]
#
#   <MediaID>  Apple keys the MusicKit Media ID (not the plain app/team ID) as the
#              JWT issuer, e.g. KVQFWJ7C7S.media.com.cshariq.sapphire
#   <KeyID>    the Apple Music API key ID, e.g. 85UU4CB24H
#   <p8>       the private key downloaded from the developer portal
#   [days]     token lifetime in days (default 180)
#   [file]     WeatherAPIKey.swift to patch (default: Sapphire/Stubs/WeatherAPIKey.swift)
#
# Requires: openssl + swift (both ship with the Xcode command line tools).
#
# To avoid rebuilding when the token expires, you can also supply it at launch:
#   export MUSICKIT_DEVELOPER_TOKEN="<token>"; open -a Sapphire
# or write ~/.sapphire/MusicKitConfig.plist with key "DeveloperToken".
#
# Personalized Apple Music features (love, play counts, recently played, For You,
# library) also need a *user* token. Sapphire reads it from (priority):
#   export MUSICKIT_USER_TOKEN="<token>"
#   ~/.sapphire/MusicKitConfig.plist  -> key "UserToken"
#   Keychain (saved automatically once obtained via the MusicKit entitlement)

set -euo pipefail

MEDIA_ID="${1:?usage: make_musickit_token.sh <MediaID> <KeyID> <AuthKey_<KeyID>.p8> [days] [WeatherAPIKey.swift]}"
KEY_ID="${2:?missing KeyID}"
P8_PATH="${3:?missing path to AuthKey_<KeyID>.p8}"
DAYS="${4:-180}"
TARGET="${5:-Sapphire/Stubs/WeatherAPIKey.swift}"

if [ ! -f "$P8_PATH" ]; then
    echo "error: private key not found: $P8_PATH" >&2
    exit 1
fi
if [ ! -f "$TARGET" ]; then
    echo "error: WeatherAPIKey.swift not found: $TARGET" >&2
    exit 1
fi

NOW=$(date +%s)
EXP=$((NOW + DAYS * 86400))

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

hdr=$(printf '{"alg":"ES256","kid":"%s"}' "$KEY_ID" | b64url)
payload=$(printf '{"iss":"%s","iat":%s,"exp":%s}' "$MEDIA_ID" "$NOW" "$EXP" | b64url)
signing_input="$hdr.$payload"

# DER-encoded ES256 signature: SEQUENCE { INTEGER r, INTEGER s }
der_b64=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$P8_PATH" -binary | openssl base64 -A)

# Parse the DER, build the raw 64-byte (r||s) signature, assemble the final JWT,
# XOR-mask it with the same LCG Sapphire's WeatherAPIKey.decode uses, and write
# it into WeatherAPIKey.swift. The masking math lives in Swift so it can never
# drift from the app's decode.
export DER_B64 SIGNING_INPUT TARGET
result=$(swift - <<'SWIFT'
import Foundation

let der = Data(base64Encoded: ProcessInfo.processInfo.environment["DER_B64"]!)!
let signingInput = ProcessInfo.processInfo.environment["SIGNING_INPUT"]!
let target = ProcessInfo.processInfo.environment["TARGET"]!

var idx = der.startIndex
func readByte() -> UInt8 {
    defer { idx = der.index(after: idx) }
    return der[idx]
}
func readLength() -> Int {
    let first = Int(readByte())
    if first & 0x80 == 0 { return first }
    let n = first & 0x7F
    var len = 0
    for _ in 0..<n { len = (len << 8) | Int(readByte()) }
    return len
}
func readInteger() -> [UInt8] {
    precondition(readByte() == 0x02, "not a DER INTEGER")
    let len = readLength()
    let start = idx
    idx = der.index(start, offsetBy: len)
    return Array(der[start..<idx])
}

precondition(readByte() == 0x30, "not a DER SEQUENCE")
_ = readLength()
let r = readInteger()
let s = readInteger()

func fixed32(_ v: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: 32)
    let tail = Array(v.suffix(32))
    for (i, b) in tail.enumerated() { out[32 - tail.count + i] = b }
    return out
}

let sig = fixed32(r) + fixed32(s)
let sigB64 = Data(sig).base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
let token = signingInput + "." + sigB64

// Mask with the same LCG as WeatherAPIKey.decode.
let mult: UInt64 = 6364136223846793005
let incr: UInt64 = 1442695040888963407
var state: UInt64 = 0x0000000000c0ffee
let encoded = Array(token.utf8).map { byte -> UInt8 in
    state = state &* mult &+ incr
    return byte ^ UInt8(truncatingIfNeeded: state >> 32)
}

// Format a Swift [UInt8] literal, 12 bytes per line.
var lines: [String] = []
var line: [String] = []
for b in encoded {
    line.append(String(format: "0x%02x", b))
    if line.count == 12 { lines.append(line.joined(separator: ", ")); line = [] }
}
if !line.isEmpty { lines.append(line.joined(separator: ", ")) }
let arrayLiteral = lines.map { "        \($0)," }.joined(separator: "\n")

var content = try String(contentsOf: URL(fileURLWithPath: target), encoding: .utf8)
let marker = "musicKitDeveloperTokenEncoded: [UInt8] = ["
guard let markerRange = content.range(of: marker) else {
    FileHandle.standardError.write(Data(
        "error: '\(marker)' not found in \(target).\n".utf8
    ))
    exit(2)
}
let contentsStart = markerRange.upperBound
guard let closing = content[contentsStart...].firstIndex(of: "]") else {
    FileHandle.standardError.write(Data(
        "error: no closing ']' found for the MusicKit token array in \(target)\n".utf8
    ))
    exit(2)
}
content.replaceSubrange(contentsStart..<closing, with: "\n" + arrayLiteral + "\n    ")
try content.write(to: URL(fileURLWithPath: target), atomically: true, encoding: .utf8)

print("minted \(token.count)-char JWT (kid \(signingInput)). 180-day-ish validity: \(ProcessInfo.processInfo.environment["DAYS"] ?? "180") days")
SWIFT
)

cat <<EOF

$result

Done. The JWT (masked byte array) is now in $TARGET.
The .p8 private key was only touching the signing step and never lands in the app.
EOF