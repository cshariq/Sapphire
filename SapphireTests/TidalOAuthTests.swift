//
//  TidalOAuthTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import XCTest
@testable import Sapphire

final class TidalOAuthTests: XCTestCase {
    @MainActor
    func testAuthorizationScopesOnlyRequestThirdPartyAccess() {
        let scopes = Set(TidalAPIManager.authorizationScopes)

        XCTAssertEqual(scopes, [
            "user.read",
            "search.read",
            "collection.read",
            "collection.write",
            "playlists.read",
            "playlists.write",
        ])
        XCTAssertFalse(scopes.contains("r_usr"))
        XCTAssertFalse(scopes.contains("w_usr"))
    }
}