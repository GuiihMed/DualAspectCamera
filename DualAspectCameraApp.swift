import SwiftUI
import UIKit

final class AppOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Lock interface to Landscape so the full 16:9 sensor feed fills the display
        // with the centered 9:16 vertical crop guide aligned to the physical sensor.
        .landscape
    }
}

@main
struct DualAspectCameraApp: App {
    @UIApplicationDelegateAdaptor(AppOrientationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            CameraView()
        }
    }
}
