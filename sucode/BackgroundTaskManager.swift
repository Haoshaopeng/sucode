//
//  BackgroundTaskManager.swift
//  sucode
//
//  后台任务和本地通知管理
//

import Foundation
import UserNotifications
import BackgroundTasks
import Combine

// MARK: - 后台任务类型
enum BackgroundTaskType: String, CaseIterable {
    case connectionKeepalive = "com.sucode.connection.keepalive"
    case deviceStatusCheck = "com.sucode.device.status"
    case commandQueue = "com.sucode.command.queue"

    var identifier: String { rawValue }
    var refreshInterval: TimeInterval {
        switch self {
        case .connectionKeepalive: return 60 * 5 // 5分钟
        case .deviceStatusCheck: return 60 * 15 // 15分钟
        case .commandQueue: return 60 * 10 // 10分钟
        }
    }
}

// MARK: - 后台任务管理器
class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()

    @Published var isBackgroundRefreshEnabled = false
    @Published var pendingNotifications: [UNNotificationRequest] = []

    private var cancellables = Set<AnyCancellable>()
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - 初始化
    private init() {
        setupNotifications()
    }

    // MARK: - 通知设置
    private func setupNotifications() {
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isBackgroundRefreshEnabled = granted
                if let error = error {
                    print("通知授权失败: \(error)")
                }
            }
        }

        // 注册通知类别
        let commandCategory = UNNotificationCategory(
            identifier: "COMMAND_RESPONSE",
            actions: [
                UNNotificationAction(identifier: "VIEW_RESULT", title: "查看结果", options: .foreground),
                UNNotificationAction(identifier: "DISMISS", title: "忽略", options: .destructive)
            ],
            intentIdentifiers: [],
            options: []
        )

        let deviceStatusCategory = UNNotificationCategory(
            identifier: "DEVICE_STATUS",
            actions: [
                UNNotificationAction(identifier: "CONNECT", title: "连接", options: .foreground),
                UNNotificationAction(identifier: "IGNORE", title: "忽略", options: .destructive)
            ],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([commandCategory, deviceStatusCategory])
    }

    // MARK: - 后台任务注册
    func registerBackgroundTasks() {
        // iOS 13+ BGTaskScheduler
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskType.connectionKeepalive.identifier, using: nil) { task in
                self.handleConnectionKeepalive(task: task as! BGAppRefreshTask)
            }

            BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskType.deviceStatusCheck.identifier, using: nil) { task in
                self.handleDeviceStatusCheck(task: task as! BGAppRefreshTask)
            }

            BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskType.commandQueue.identifier, using: nil) { task in
                self.handleCommandQueue(task: task as! BGProcessingTask)
            }
        }

        print("后台任务已注册")
    }

    // MARK: - 调度后台任务
    @available(iOS 13.0, *)
    func scheduleBackgroundTasks() {
        // 连接保活
        let keepaliveRequest = BGAppRefreshTaskRequest(identifier: BackgroundTaskType.connectionKeepalive.identifier)
        keepaliveRequest.earliestBeginDate = Date(timeIntervalSinceNow: BackgroundTaskType.connectionKeepalive.refreshInterval)

        // 设备状态检查
        let statusRequest = BGAppRefreshTaskRequest(identifier: BackgroundTaskType.deviceStatusCheck.identifier)
        statusRequest.earliestBeginDate = Date(timeIntervalSinceNow: BackgroundTaskType.deviceStatusCheck.refreshInterval)

        // 命令队列处理
        let commandRequest = BGProcessingTaskRequest(identifier: BackgroundTaskType.commandQueue.identifier)
        commandRequest.requiresNetworkConnectivity = true
        commandRequest.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(keepaliveRequest)
            try BGTaskScheduler.shared.submit(statusRequest)
            try BGTaskScheduler.shared.submit(commandRequest)
            print("后台任务已调度")
        } catch {
            print("调度后台任务失败: \(error)")
        }
    }

    // MARK: - 后台任务处理
    @available(iOS 13.0, *)
    private func handleConnectionKeepalive(task: BGAppRefreshTask) {
        let queue = DispatchQueue(label: "com.sucode.keepalive")
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        queue.async {
            // 检查活跃连接并保活
            // TODO: 实现具体的保活逻辑
            self.scheduleBackgroundTasks() // 重新调度
            task.setTaskCompleted(success: true)
        }
    }

    @available(iOS 13.0, *)
    private func handleDeviceStatusCheck(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // 检查设备在线状态
        Task {
            await checkDeviceStatus()
            task.setTaskCompleted(success: true)
        }
    }

    @available(iOS 13.0, *)
    private func handleCommandQueue(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // 处理排队的命令
        Task {
            await processQueuedCommands()
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - 设备状态检查
    private func checkDeviceStatus() async {
        // TODO: 检查保存的设备连接状态
        // 如果发现设备离线/在线状态变化，发送通知
    }

    // MARK: - 命令队列处理
    private func processQueuedCommands() async {
        // TODO: 处理后台排队的命令
    }

    // MARK: - 发送本地通知
    func sendNotification(title: String, body: String, category: String? = nil, delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if let category = category {
            content.categoryIdentifier = category
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay > 0 ? delay : 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        notificationCenter.add(request) { error in
            if let error = error {
                print("发送通知失败: \(error)")
            }
        }
    }

    // MARK: - 命令完成通知
    func notifyCommandComplete(deviceName: String, command: String, success: Bool) {
        let title = success ? "✅ 命令执行完成" : "❌ 命令执行失败"
        let body = "[\(deviceName)] \(command.prefix(30))\(command.count > 30 ? "..." : "")"
        sendNotification(title: title, body: body, category: "COMMAND_RESPONSE")
    }

    // MARK: - 设备状态通知
    func notifyDeviceStatusChange(deviceName: String, isOnline: Bool) {
        let title = isOnline ? "🟢 设备上线" : "🔴 设备离线"
        let body = "\(deviceName) 现在\(isOnline ? "在线" : "离线")"
        sendNotification(title: title, body: body, category: "DEVICE_STATUS")
    }

    // MARK: - 取消所有通知
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }
}

// MARK: - App Delegate 扩展
import UIKit

class SucodeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // 注册后台任务
        BackgroundTaskManager.shared.registerBackgroundTasks()

        // 设置后台获取（旧版 API）
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

        return true
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // 旧版后台获取处理
        Task {
            // 执行后台任务
            completionHandler(.newData)
        }
    }

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
