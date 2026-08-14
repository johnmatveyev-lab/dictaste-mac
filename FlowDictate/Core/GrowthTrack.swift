import Foundation

/// Fire-and-forget first-party activation events. No PII. Once per install per event.
enum GrowthTrack {
    private static let endpoint = URL(string: "https://dictaste.vercel.app/api/track")!

    static func once(_ event: String, props: [String: String] = [:]) {
        let key = "dt_track_\(event)"
        if UserDefaults.standard.bool(forKey: key) { return }
        UserDefaults.standard.set(true, forKey: key)
        fire(event, props: props)
    }

    static func fire(_ event: String, props: [String: String] = [:]) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        var merged = props
        merged["os"] = "mac"
        merged["path"] = "app"
        let body: [String: Any] = ["event": event, "props": merged]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }
}
