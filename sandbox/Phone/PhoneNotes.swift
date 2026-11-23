import SwiftUI
import UserNotifications

/// Notifications as notes, led by the agent's monogram: the brief from Leo, a capture saved by Bolton.
@MainActor
enum PhoneNotes {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(agent: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url = monogram(agent), let attachment = try? UNNotificationAttachment(identifier: agent, url: url) {
            content.attachments = [attachment]
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// The agent's circle as a picture for the notification to lead with. A fresh file each time: the system keeps it.
    private static func monogram(_ agent: String) -> URL? {
        let renderer = ImageRenderer(content: PhoneAgentCircle(code: agent, size: 120, style: .ink))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("monogram-\(agent)-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}
