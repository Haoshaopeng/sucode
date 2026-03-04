import SwiftUI
import SwiftData

@main
struct sucodeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var persistence = DataPersistenceManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(persistence.theme.colorScheme)
                .environmentObject(persistence)
        }
        .modelContainer(PersistenceManager.shared.container)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Configure default settings
        _ = DataPersistenceManager.shared

        // 数据迁移到 SwiftData（如果需要）
        Task {
            await DataPersistenceManager.shared.migrateToSwiftData()
        }

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Save any pending data
        DataPersistenceManager.shared.saveDevices(DataPersistenceManager.shared.loadDevices())

        // 保存会话状态到 SwiftData
        Task {
            try? await PersistenceManager.shared.saveSessionState(
                selectedTab: DataPersistenceManager.shared.lastSelectedTab,
                selectedDeviceId: DataPersistenceManager.shared.getLastSelectedDevice()
            )
        }
    }
}
