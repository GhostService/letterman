import Foundation

enum Config {
    /// Your PocketBase server. Change this if you move to a different domain.
    static let productionURL = URL(string: "https://hours.tiredghost.com")!

    /// Debug builds in the Simulator talk to PocketBase running on this Mac (see docs/IOS_SETUP.md).
    /// Everything else, including the app on your iPhone, uses the real server.
    static var baseURL: URL {
        #if DEBUG && targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8090")!
        #else
        return productionURL
        #endif
    }
}
