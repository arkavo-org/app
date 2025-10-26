import SwiftUI

@main
struct ArkavoTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            CalibrationView()
                .onAppear {
                    print("ArkavoTestHost: Starting calibration immediately")
                }
        }
    }
}
