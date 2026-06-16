// Recall notifier — posts macOS notifications via the modern UserNotifications
// framework (works on current macOS, unlike terminal-notifier's legacy API) and
// opens a vscode:// URL when the notification is clicked.
//
// Usage:
//   RecallNotifier post --title T --subtitle S --message M --url U --id ID [--sound]
//   RecallNotifier remove --id ID
//   (launched with no args -> it was opened by a notification click; opens its URL)
import Cocoa
import UserNotifications

func log(_ s: String) {
    let line = "\(Date()) \(s)\n"
    let p = (NSHomeDirectory() as NSString).appendingPathComponent(".recall/notifier.log")
    if let d = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: p) { fh.seekToEndOfFile(); fh.write(d); fh.closeFile() }
        else { try? line.write(toFile: p, atomically: true, encoding: .utf8) }
    }
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return nil
}
func hasFlag(_ name: String) -> Bool { CommandLine.arguments.contains(name) }
func bye(_ after: Double = 0.3) {
    DispatchQueue.main.asyncAfter(deadline: .now() + after) { NSApp.terminate(nil) }
}

final class Delegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "wait"
        log("launched argv=\(CommandLine.arguments) bundleId=\(Bundle.main.bundleIdentifier ?? "nil")")

        switch mode {
        case "post":
            center.getNotificationSettings { s in
                log("auth status before request: \(s.authorizationStatus.rawValue)")
            }
            center.requestAuthorization(options: [.alert, .sound]) { granted, err in
                log("auth granted=\(granted) err=\(String(describing: err))")
                guard granted else { bye(); return }
                let content = UNMutableNotificationContent()
                content.title = arg("--title") ?? "Claude"
                if let s = arg("--subtitle") { content.subtitle = s }
                content.body = arg("--message") ?? ""
                if let u = arg("--url") { content.userInfo = ["url": u] }
                if hasFlag("--sound") { content.sound = .default }
                let id = arg("--id") ?? UUID().uuidString
                let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
                center.add(req) { e in log("add err=\(String(describing: e))"); bye(0.6) }
            }
        case "remove":
            if let id = arg("--id") {
                center.removeDeliveredNotifications(withIdentifiers: [id])
            }
            bye(0.2)
        default:
            // No args -> launched by a notification click; wait for didReceive.
            bye(4.0)
        }
    }

    // Show the banner even if our (accessory) app is frontmost.
    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .list, .sound])
    }

    // The click: open the stored vscode:// URL.
    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                didReceive r: UNNotificationResponse,
                                withCompletionHandler h: @escaping () -> Void) {
        if let s = r.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
        h()
        bye(0.2)
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
