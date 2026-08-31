//
//  SportsFinanceContentProvider.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import Foundation

enum SportsFinanceContentProvider {
    static func makeSportsPayload(from live: LiveSportsEvent) -> SportsPayload {
        SportsPayload(
            league: live.leagueRoute.displayName,
            homeTeam: live.homeTeam,
            awayTeam: live.awayTeam,
            homeScore: live.homeScore,
            awayScore: live.awayScore,
            status: live.isLive ? "Live" : live.status,
            time: live.clock,
            league_logo: nil,
            homeLogoURL: live.homeLogoURL,
            awayLogoURL: live.awayLogoURL
        )
    }

    static func makeSportsPayload(for teamOrLeague: String, index: Int) -> SportsPayload {
        SportsPayload(
            league: "",
            homeTeam: teamOrLeague,
            awayTeam: "TBD",
            homeScore: 0,
            awayScore: 0,
            status: "Upcoming",
            time: "--:--"
        )
    }
}