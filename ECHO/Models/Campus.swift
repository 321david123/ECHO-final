//
//  Campus.swift
//  ECHO
//

import Foundation
import CoreLocation

/// A Mexican university campus — feed is scoped to one campus.
struct Campus: Identifiable, Equatable {
    let id: String
    let name: String
    let shortName: String
    let city: String
    let coordinate: CLLocationCoordinate2D?
    /// Allowed email domains for verification (e.g. ["tec.mx", "itesm.mx"]). Only these can sign in for this campus.
    let allowedEmailDomains: [String]
    
    static func == (lhs: Campus, rhs: Campus) -> Bool {
        guard lhs.id == rhs.id, lhs.name == rhs.name, lhs.shortName == rhs.shortName, lhs.city == rhs.city else { return false }
        switch (lhs.coordinate, rhs.coordinate) {
        case (nil, nil): return true
        case let (a?, b?): return a.latitude == b.latitude && a.longitude == b.longitude
        default: return false
        }
    }
    
    /// Returns true if the email's domain is allowed for this campus.
    func allows(email: String) -> Bool {
        let lower = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.contains("@"), let domain = lower.split(separator: "@").last.map(String.init) else { return false }
        return allowedEmailDomains.contains { domain == $0.lowercased() || domain.hasSuffix("." + $0.lowercased()) }
    }
    
    /// Tec Querétaro first; rest unchanged.
    static let mexicanUniversities: [Campus] = [
        Campus(id: "tec-queretaro", name: "Tec de Monterrey - Querétaro", shortName: "Tec Qro", city: "Querétaro", coordinate: nil, allowedEmailDomains: ["tec.mx", "itesm.mx"]),
        Campus(id: "tec-monterrey", name: "Tecnológico de Monterrey", shortName: "Tec", city: "Monterrey", coordinate: CLLocationCoordinate2D(latitude: 25.6516, longitude: -100.2895), allowedEmailDomains: ["tec.mx", "itesm.mx"]),
        Campus(id: "tec-gdl", name: "Tec de Monterrey - Guadalajara", shortName: "Tec GDL", city: "Guadalajara", coordinate: CLLocationCoordinate2D(latitude: 20.6736, longitude: -103.3444), allowedEmailDomains: ["tec.mx", "itesm.mx"]),
        Campus(id: "tec-cdmx", name: "Tec de Monterrey - CDMX", shortName: "Tec CDMX", city: "Ciudad de México", coordinate: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332), allowedEmailDomains: ["tec.mx", "itesm.mx"]),
        Campus(id: "unam", name: "UNAM", shortName: "UNAM", city: "Ciudad de México", coordinate: CLLocationCoordinate2D(latitude: 19.3328, longitude: -99.1865), allowedEmailDomains: ["unam.mx", "comunidad.unam.mx", "alumno.unam.mx"]),
        Campus(id: "itam", name: "ITAM", shortName: "ITAM", city: "Ciudad de México", coordinate: CLLocationCoordinate2D(latitude: 19.3460, longitude: -99.1927), allowedEmailDomains: ["itam.mx"]),
        Campus(id: "ibero", name: "Universidad Iberoamericana", shortName: "Ibero", city: "Ciudad de México", coordinate: CLLocationCoordinate2D(latitude: 19.3586, longitude: -99.2662), allowedEmailDomains: ["ibero.mx", "uia.mx"]),
        Campus(id: "anahuac", name: "Universidad Anáhuac", shortName: "Anáhuac", city: "Ciudad de México", coordinate: nil, allowedEmailDomains: ["anahuac.mx"]),
        Campus(id: "udlap", name: "UDLAP", shortName: "UDLAP", city: "Puebla", coordinate: CLLocationCoordinate2D(latitude: 19.0489, longitude: -98.2434), allowedEmailDomains: ["udlap.mx"]),
        Campus(id: "tec-puebla", name: "Tec de Monterrey - Puebla", shortName: "Tec Puebla", city: "Puebla", coordinate: nil, allowedEmailDomains: ["tec.mx", "itesm.mx"]),
    ]
}
