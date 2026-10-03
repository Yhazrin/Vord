import Foundation

enum BrowserIntegrationIdentity {
    static let extensionID = "jnmhnjkpcmbegdgphhgccdodoejajkab"
    static let hostName = "app.vord.selection"
    static var origin: String { "chrome-extension://" + extensionID + "/" }
}
