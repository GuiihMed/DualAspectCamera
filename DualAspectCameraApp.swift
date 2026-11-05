import SwiftUI
import UIKit

final class AppOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Support both Portrait and Landscape fluid responsiveness
        .allButUpsideDown
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
