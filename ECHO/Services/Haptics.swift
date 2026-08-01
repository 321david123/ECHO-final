//
//  Haptics.swift
//  ECHO
//

import UIKit

enum Haptics {
    /// Two very small taps in quick succession. Used when the user upvotes/downvotes.
    static func voteTick() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            generator.impactOccurred(intensity: 0.5)
        }
    }
    
    /// Two taps a bit stronger than `voteTick`. Used when the user publishes a post.
    static func postPublished() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            generator.impactOccurred(intensity: 0.75)
        }
    }
}
