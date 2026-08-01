//
//  ShareLinks.swift
//  ECHO
//
//  Share links via GitHub Pages + Universal Links.
//  URL format: https://<github-user>.github.io/s/<post-id>
//
//  - App instalada → iOS abre el post directo (Universal Link).
//  - App no instalada → GitHub Pages sirve 404.html que redirige a la App Store.
//

import Foundation

enum ShareLinks {
    static let baseURL: String = {
        if let env = ProcessInfo.processInfo.environment["ECHO_SHARE_BASE_URL"], !env.isEmpty {
            return env.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "ECHO_SHARE_BASE_URL") as? String, !plist.isEmpty {
            return plist.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "https://321david123.github.io"
    }()
    
    static func url(for postId: UUID) -> URL {
        URL(string: "\(baseURL)/s/\(postId.uuidString.lowercased())")!
    }
    
    static func text(for post: Post) -> String {
        let trimmed = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = trimmed.count > 220 ? String(trimmed.prefix(220)) + "…" : trimmed
        return "\"\(snippet)\"\n\nVisto en ECHO\n\(url(for: post.id).absoluteString)"
    }
    
    static func postId(from url: URL) -> UUID? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[parts.count - 2] == "s" else { return nil }
        return UUID(uuidString: parts.last ?? "")
    }

    // MARK: - Invite links ("Invita y Gana"): https://<base>/i/<CODE>

    static func inviteURL(for code: String) -> URL {
        URL(string: "\(baseURL)/i/\(code.uppercased())")!
    }

    /// Share text for inviting a friend with your referral code.
    static func inviteText(code: String, campusShortName: String) -> String {
        """
        🗣️ Ya estoy en Echo, la app anónima del \(campusShortName). Chisme, avisos y memes del campus.

        Descárgala, regístrate con tu correo del Tec y cuando te pregunte quién te invitó pon mi código: \(code)

        Si entras ahora eres de los primeros: hay badge OG 🐿️, perfil dorado y bebidas gratis — solo durante el lanzamiento 👀

        \(inviteURL(for: code).absoluteString)
        """
    }

    /// Parse an invite code from a universal link (…/i/ABC123). 6 chars, alphanumeric.
    static func inviteCode(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[parts.count - 2] == "i" else { return nil }
        let code = (parts.last ?? "").uppercased()
        guard code.count == 6, code.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return code
    }
}
