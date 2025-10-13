import KeyboardShortcuts
import SwiftState
import SwiftUI
import Foundation
import CryptoKit

// Data 扩展，用于转换为十六进制字符串
extension Data {
    func hexEncodedString() -> String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
}


// 工作完成数据结构
struct WorkCompletionData {
    let description: String
    let tags: [String]
    let startTime: Date
    let endTime: Date

    init(description: String, tags: [String], startTime: Date, endTime: Date = Date()) {
        self.description = description
        self.tags = tags
        self.startTime = startTime
        self.endTime = endTime
    }
}

// 工作完成视图
struct WorkCompletionView: View {
    @Environment(\.presentationMode) var presentationMode
    @SwiftUI.State private var workDescription = ""
    @SwiftUI.State private var isSubmitting = false
    @SwiftUI.State private var showAlert = false
    @SwiftUI.State private var alertMessage = ""
    @SwiftUI.State private var alertTitle = ""

    let startTime: Date
    let endTime: Date
    let onCompletion: (WorkCompletionData) -> Void

    init(startTime: Date, endTime: Date, onCompletion: @escaping (WorkCompletionData) -> Void) {
        self.startTime = startTime
        self.endTime = endTime
        self.onCompletion = onCompletion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("WorkCompletionView.title", comment: "Work completion title"))
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("WorkCompletionView.time.label", comment: "Time period label"))
                    .font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("WorkCompletionView.startTime.label", comment: "Start time label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatTime(startTime))
                            .font(.system(.body, design: .monospaced))
                    }

                    Spacer()

                    Text("→")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("WorkCompletionView.endTime.label", comment: "End time label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatTime(endTime))
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("WorkCompletionView.description.label", comment: "Work description label"))
                    .font(.headline)
                TextEditor(text: $workDescription)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }

  
            HStack {
                Button(NSLocalizedString("WorkCompletionView.cancel", comment: "Cancel button")) {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(NSLocalizedString("WorkCompletionView.skip", comment: "Skip button")) {
                    onCompletion(WorkCompletionData(description: "", tags: [], startTime: startTime, endTime: endTime))
                    presentationMode.wrappedValue.dismiss()
                }

                Button(NSLocalizedString("WorkCompletionView.submit", comment: "Submit button")) {
                    submitWork()
                }
                .keyboardShortcut(.return)
                .disabled(isSubmitting || workDescription.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 320)
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text(NSLocalizedString("OK", comment: "OK button"))))
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func submitWork() {
        isSubmitting = true

        let completionData = WorkCompletionData(description: workDescription, tags: [], startTime: startTime, endTime: endTime)

        // 通过回调让TBTimer处理上传，避免直接引用WorkCompletionService
        onCompletion(completionData)

        // 显示提交成功的消息
        alertTitle = NSLocalizedString("WorkCompletionView.success.title", comment: "Success title")
        alertMessage = NSLocalizedString("WorkCompletionView.success.message", comment: "Success message")
        showAlert = true

        // 延迟关闭弹窗
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSubmitting = false
            presentationMode.wrappedValue.dismiss()
        }
    }
}

class TBTimer: ObservableObject {
    @AppStorage("stopAfterBreak") var stopAfterBreak = false
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4
    // This preference is "hidden"
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0

    private var stateMachine = TBStateMachine(state: .idle)
    public let player = TBPlayer()
    private var consecutiveWorkIntervals: Int = 0
    private var notificationCenter = TBNotificationCenter()
    private var finishTime: Date!
    private var workStartTime: Date!
    private var timerFormatter = DateComponentsFormatter()
    @Published var timeLeftString: String = ""
    @Published var timer: DispatchSourceTimer?
    private var workCompletionWindows: [WorkCompletionWindow] = []
    private var pendingWorkCompletionData: WorkCompletionData?

    init() {
        /*
         * State diagram
         *
         *                 start/stop
         *       +--------------+-------------+
         *       |              |             |
         *       |  start/stop  |  timerFired |
         *       V    |         |    |        |
         * +--------+ |  +--------+  | +--------+
         * | idle   |--->| work   |--->| rest   |
         * +--------+    +--------+    +--------+
         *   A                  A        |    |
         *   |                  |        |    |
         *   |                  +--------+    |
         *   |  timerFired (!stopAfterBreak)  |
         *   |             skipRest           |
         *   |                                |
         *   +--------------------------------+
         *      timerFired (stopAfterBreak)
         *
         */
        stateMachine.addRoutes(event: .startStop, transitions: [
            .idle => .work, .work => .idle, .rest => .idle,
        ])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .rest])
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .idle]) { _ in
            self.stopAfterBreak
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .work]) { _ in
            !self.stopAfterBreak
        }
        stateMachine.addRoutes(event: .skipRest, transitions: [.rest => .work])

        /*
         * "Finish" handlers are called when time interval ended
         * "End"    handlers are called when time interval ended or was cancelled
         */
        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.work => .rest, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .any, order: 1, handler: onWorkEnd)
        stateMachine.addAnyHandler(.any => .rest, handler: onRestStart)
        stateMachine.addAnyHandler(.rest => .work, handler: onRestFinish)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)
        stateMachine.addAnyHandler(.any => .any, handler: { ctx in
            logger.append(event: TBLogEventTransition(fromContext: ctx))
        })

        stateMachine.addErrorHandler { ctx in fatalError("state machine context: <\(ctx)>") }

        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: startStop)
        notificationCenter.setActionHandler(handler: onNotificationAction)

        let aem: NSAppleEventManager = NSAppleEventManager.shared()
        aem.setEventHandler(self,
                            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                            forEventClass: AEEventClass(kInternetEventClass),
                            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue else {
            print("url handling error: cannot get url")
            return
        }
        let url = URL(string: urlString)
        guard url != nil,
              let scheme = url!.scheme,
              let host = url!.host else {
            print("url handling error: cannot parse url")
            return
        }
        guard scheme.caseInsensitiveCompare("tomatobar") == .orderedSame else {
            print("url handling error: unknown scheme \(scheme)")
            return
        }
        switch host.lowercased() {
        case "startstop":
            startStop()
        default:
            print("url handling error: unknown command \(host)")
            return
        }
    }

    func startStop() {
        stateMachine <-! .startStop
    }

    func skipRest() {
        stateMachine <-! .skipRest
    }

    func updateTimeLeft() {
        timeLeftString = timerFormatter.string(from: Date(), to: finishTime)!
        if timer != nil, showTimerInMenuBar {
            TBStatusItem.shared.setTitle(title: timeLeftString)
        } else {
            TBStatusItem.shared.setTitle(title: nil)
        }
    }

    private func startTimer(seconds: Int) {
        finishTime = Date().addingTimeInterval(TimeInterval(seconds))

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer!.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer!.setEventHandler(handler: onTimerTick)
        timer!.setCancelHandler(handler: onTimerCancel)
        timer!.resume()
    }

    private func stopTimer() {
        timer!.cancel()
        timer = nil
    }

    private func onTimerTick() {
        /* Cannot publish updates from background thread */
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
            let timeLeft = finishTime.timeIntervalSince(Date())
            if timeLeft <= 0 {
                /*
                 Ticks can be missed during the machine sleep.
                 Stop the timer if it goes beyond an overrun time limit.
                 */
                if timeLeft < overrunTimeLimit {
                    stateMachine <-! .startStop
                } else {
                    stateMachine <-! .timerFired
                }
            }
        }
    }

    private func onTimerCancel() {
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        if action == .skipRest, stateMachine.state == .rest {
            skipRest()
        }
    }

    private func onWorkStart(context _: TBStateMachine.Context) {
        TBStatusItem.shared.setIcon(name: .work)
        player.playWindup()
        player.startTicking()
        workStartTime = Date()
        startTimer(seconds: workIntervalLength * 60)
    }

    private func onWorkFinish(context _: TBStateMachine.Context) {
        consecutiveWorkIntervals += 1
        player.playDing()

        // 显示工作完成弹窗，传递实际的工作开始和结束时间
        DispatchQueue.main.async {
            self.showWorkCompletionWindow(startTime: self.workStartTime, endTime: Date())
        }
    }

    private func onWorkEnd(context _: TBStateMachine.Context) {
        player.stopTicking()
    }

    private func onRestStart(context _: TBStateMachine.Context) {
        var body = NSLocalizedString("TBTimer.onRestStart.short.body", comment: "Short break body")
        var length = shortRestIntervalLength
        var imgName = NSImage.Name.shortRest
        if consecutiveWorkIntervals >= workIntervalsInSet {
            body = NSLocalizedString("TBTimer.onRestStart.long.body", comment: "Long break body")
            length = longRestIntervalLength
            imgName = .longRest
            consecutiveWorkIntervals = 0
        }
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
            body: body,
            category: .restStarted
        )
        TBStatusItem.shared.setIcon(name: imgName)
        startTimer(seconds: length * 60)
    }

    private func onRestFinish(context ctx: TBStateMachine.Context) {
        if ctx.event == .skipRest {
            return
        }
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
            body: NSLocalizedString("TBTimer.onRestFinish.body", comment: "Break is over body"),
            category: .restFinished
        )
    }

    private func onIdleStart(context _: TBStateMachine.Context) {
        stopTimer()
        TBStatusItem.shared.setIcon(name: .idle)
        consecutiveWorkIntervals = 0
    }

    private func showWorkCompletionWindow(startTime: Date, endTime: Date) {
        // 创建默认的工作完成数据（空描述和标签）
        pendingWorkCompletionData = WorkCompletionData(description: "", tags: [], startTime: startTime, endTime: endTime)

        var workCompletionWindow: WorkCompletionWindow!
        workCompletionWindow = WorkCompletionWindow(startTime: startTime, endTime: endTime, onCompletion: { [weak self] completionData in
            self?.handleWorkCompletion(completionData)
        }, onClose: { [weak self, weak workCompletionWindow] in
            guard let self = self, let window = workCompletionWindow else { return }
            self.removeWorkCompletionWindow(window)
        })

        // 将窗口添加到数组中
        workCompletionWindows.append(workCompletionWindow)
        workCompletionWindow.show()
    }

    private func handleWorkCompletion(_ data: WorkCompletionData) {
        // 先保存到本地作为备份
        saveWorkCompletionLocally(data)
        print("工作记录已保存到本地")

        // 如果有描述，尝试上传到服务器
        if !data.description.isEmpty {
            attemptUploadWorkCompletion(data)
        }
    }

    private func attemptUploadWorkCompletion(_ data: WorkCompletionData) {
        // 获取API配置
        let apiEndpoint = UserDefaults.standard.string(forKey: "WorkCompletionAPIEndpoint") ?? ""
        let appId = UserDefaults.standard.string(forKey: "WorkCompletionAppId") ?? ""
        let appSecret = UserDefaults.standard.string(forKey: "WorkCompletionAppSecret") ?? ""

        // 检查配置
        guard !apiEndpoint.isEmpty, !appId.isEmpty, !appSecret.isEmpty else {
            print("未配置API端点或认证信息，跳过上传")
            return
        }

        // 创建URL请求
        guard let url = URL(string: apiEndpoint) else {
            print("无效的API地址")
            return
        }

        // 创建时间戳
        let timestamp = String(Int(Date().timeIntervalSince1970))

        // 创建请求数据
        let requestData: [String: Any] = [
            "client": "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "description": data.description,
            "end_time": ISO8601DateFormatter().string(from: data.endTime),
            "source": "TomatoBar App",
            "start_time": ISO8601DateFormatter().string(from: data.startTime)
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData) else {
            print("无法编码数据")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 生成签名
        guard let signature = generateSignature(for: request, appId: appId, timestamp: timestamp, secret: appSecret) else {
            print("签名生成失败")
            return
        }

        // 添加认证头
        request.setValue(appId, forHTTPHeaderField: "X-App-ID")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
        request.httpBody = jsonData

        // 执行网络请求
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("上传失败: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    guard 200...299 ~= httpResponse.statusCode else {
                        print("服务器错误: \(httpResponse.statusCode)")
                        return
                    }
                }

                print("工作记录已上传到服务器")
            }
        }

        task.resume()
    }

    // 生成签名（HMAC-SHA256）
    private func generateSignature(for request: URLRequest, appId: String, timestamp: String, secret: String) -> String? {
        guard let url = request.url else {
            return nil
        }

        // 获取请求方法
        let method = request.httpMethod ?? "POST"

        // 获取路径
        let path = url.path

        // 构建签名字符串
        let signingString = "\(method)\n\(path)\n\n\(timestamp)\n\(appId)"

        // 使用HMAC-SHA256生成签名
        guard let keyData = secret.data(using: .utf8),
              let stringData = signingString.data(using: .utf8) else {
            return nil
        }

        let digest = HMAC<SHA256>.authenticationCode(for: stringData, using: SymmetricKey(data: keyData))
        let signature = Data(digest).hexEncodedString()

        return signature
    }

    private func saveWorkCompletionLocally(_ data: WorkCompletionData) {
        let userDefaults = UserDefaults.standard
        var savedCompletions = userDefaults.array(forKey: "SavedWorkCompletions") as? [[String: Any]] ?? []

        let formatter = ISO8601DateFormatter()
        let completionDict: [String: Any] = [
            "description": data.description,
            "tags": data.tags,
            "start_time": formatter.string(from: data.startTime),
            "end_time": formatter.string(from: data.endTime)
        ]

        savedCompletions.append(completionDict)

        // 保留最近100条记录
        if savedCompletions.count > 100 {
            savedCompletions = Array(savedCompletions.suffix(100))
        }

        userDefaults.set(savedCompletions, forKey: "SavedWorkCompletions")
    }

    
    private func clearPendingWorkCompletion() {
        pendingWorkCompletionData = nil
    }

    private func removeWorkCompletionWindow(_ window: WorkCompletionWindow) {
        workCompletionWindows.removeAll { $0 === window }
    }
}

// WorkCompletionWindow 类定义
class WorkCompletionWindow: NSWindowController, NSWindowDelegate {
    private var onCompletion: ((WorkCompletionData) -> Void)?
    private var onClose: (() -> Void)?
    private var startTime: Date
    private var endTime: Date

    init(startTime: Date, endTime: Date, onCompletion: @escaping (WorkCompletionData) -> Void, onClose: @escaping () -> Void) {
        self.startTime = startTime
        self.endTime = endTime
        self.onCompletion = onCompletion
        self.onClose = onClose

        let workCompletionView = WorkCompletionView(startTime: startTime, endTime: endTime, onCompletion: onCompletion)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("WorkCompletionView.title", comment: "Work completion title")
        window.contentViewController = NSHostingController(rootView: workCompletionView)
        window.center()
        window.level = .floating

        super.init(window: window)

        // 设置delegate
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func autoSubmit() {
        // 自动提交空的工作完成数据
        let autoData = WorkCompletionData(description: "", tags: [], startTime: startTime, endTime: endTime)
        onCompletion?(autoData)

        // 显示自动提交通知
        showAutoSubmitNotification()

        window?.close()
    }

    private func showAutoSubmitNotification() {
        let notification = NSUserNotification()
        notification.title = NSLocalizedString("WorkCompletionView.autoSubmit.title", comment: "Auto-submitted")
        notification.informativeText = NSLocalizedString("WorkCompletionView.autoSubmit.message", comment: "Auto-submitted message")
        NSUserNotificationCenter.default.deliver(notification)
    }

    // NSWindowDelegate 方法
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时不自动提交数据
        // 调用onClose回调，让TBTimer从数组中移除这个窗口
        onClose?()
        // 清理回调，避免内存泄漏
        onCompletion = nil
        onClose = nil
    }
}

