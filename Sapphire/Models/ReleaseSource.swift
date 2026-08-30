//
//  ReleaseSource.swift
//  Sapphire
//

import Foundation

enum ReleaseSource {
    static let owner = "Idan-sh"
    static let repo = "SapphireNotch"

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)")!
    }

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases")!
    }

    static var releasesAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=30")!
    }
}
