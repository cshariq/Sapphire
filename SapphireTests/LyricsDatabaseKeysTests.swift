//
//  LyricsDatabaseKeysTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Testing
@testable import Sapphire

@Suite("Lyrics database keys")
struct LyricsDatabaseKeysTests {
    @Test("Hashes exactly like the importer")
    func sharedVectors() {
        #expect(
            LyricsDatabaseKeys.metadataKey(title: "Placeholder Song", artist: "Placeholder Artist")
                == "meta:ed56ea04ec93c46f5440e67fa1c5cf99"
        )
        #expect(
            LyricsDatabaseKeys.metadataKey(title: "Café Déjà Vu (feat. Guest)", artist: "Ünïcode Artist & Friend")
                == "meta:f6508ae2ec4e8af9f38ad0619d35992a"
        )
    }

    @Test("Normalizes titles and artists like the importer")
    func normalization() {
        #expect(LyricsDatabaseKeys.normalize("Café Song (feat. Someone Else)") == "cafe song")
        #expect(LyricsDatabaseKeys.normalize("Song - 2011 Remastered Version") == "song")
        #expect(LyricsDatabaseKeys.normalize("  Hello,   World!  ") == "hello world")
        #expect(LyricsDatabaseKeys.primaryArtist("Alpha & Beta, Gamma") == "Alpha")
        #expect(LyricsDatabaseKeys.primaryArtist("Florence and the Machine") == "Florence and the Machine")
        #expect(LyricsDatabaseKeys.metadataKey(title: "", artist: "Artist") == nil)
    }

    @Test("Builds platform keys")
    func platformKeys() {
        #expect(LyricsDatabaseKeys.spotifyKey("1dNIEtp7AY3oDAKCGg2XkH") == "spotify:1dNIEtp7AY3oDAKCGg2XkH")
        #expect(LyricsDatabaseKeys.appleMusicKey("1488408568") == "am:1488408568")
        #expect(LyricsDatabaseKeys.isrcKey("usug11904206") == "isrc:USUG11904206")
    }
}