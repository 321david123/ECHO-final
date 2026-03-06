//
//  Color+Theme.swift
//  ECHO
//

import SwiftUI

extension Color {
    // MARK: - Dark theme (black / near-black)
    /// App background — black.
    static let echoBackground = Color.black
    /// Slightly lighter for cards/rows.
    static let echoCard = Color(red: 0.11, green: 0.11, blue: 0.12)
    /// Nav bar / toolbar area.
    static let echoBar = Color(red: 0.06, green: 0.06, blue: 0.06)
    
    /// Primary accent — teal (vote count, avatar).
    static let echoGreen = Color(red: 0.30, green: 0.85, blue: 0.65)
    /// Downvote / warning accent.
    static let echoOrange = Color(red: 0.95, green: 0.5, blue: 0.2)
    
    /// Primary text on dark.
    static let echoText = Color.white
    /// Secondary text.
    static let echoTextSecondary = Color(red: 0.65, green: 0.65, blue: 0.68)
    /// Tertiary / captions, timestamps.
    static let echoTextTertiary = Color(red: 0.5, green: 0.5, blue: 0.53)
    /// Dark gray for vote button circles.
    static let echoVoteCircle = Color(red: 0.22, green: 0.22, blue: 0.24)
    /// Thin 1pt separator between posts (light gray).
    static let echoSeparator = Color(red: 0.35, green: 0.35, blue: 0.38)
}
