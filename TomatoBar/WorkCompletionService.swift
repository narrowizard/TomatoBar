import Foundation
import CryptoKit

class WorkCompletionService {
    static let shared = WorkCompletionService()

    private init() {}

    // 从用户配置中获取API端点，默认为空字符串（不上传）
    private var apiEndpoint: String {
        return UserDefaults.standard.string(forKey: "WorkCompletionAPIEndpoint") ?? ""
    }

    // 获取App ID
    private var appId: String {
        return UserDefaults.standard.string(forKey: "WorkCompletionAppId") ?? ""
    }

    // 获取App Secret
    private var appSecret: String {
        return UserDefaults.standard.string(forKey: "WorkCompletionAppSecret") ?? ""
    }

    func uploadWorkCompletion(_ data: WorkCompletionRecord, completion: @escaping (Result<Void, Error>) -> Void) {
        // 检查是否配置了API端点
        guard !apiEndpoint.isEmpty else {
            completion(.failure(WorkCompletionError.noEndpointConfigured))
            return
        }

        // 检查是否配置了App ID和App Secret（如果需要签名认证）
        let needsAuth = !appId.isEmpty || !appSecret.isEmpty
        if needsAuth && (appId.isEmpty || appSecret.isEmpty) {
            completion(.failure(WorkCompletionError.missingAuthCredentials))
            return
        }

        // 创建基础数据结构，匹配API要求的格式
        var requestData: [String: Any] = [
            "client": "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "description": data.description,
            "end_time": ISO8601DateFormatter().string(from: data.endTime),
            "source": "TomatoBar App",
            "start_time": ISO8601DateFormatter().string(from: data.startTime)
        ]

        // 如果需要认证，添加App ID和签名
        if needsAuth {
            requestData["app_id"] = appId

            if let signature = generateSignature(for: requestData, secret: appSecret) {
                requestData["signature"] = signature
            } else {
                completion(.failure(WorkCompletionError.signatureGenerationFailed))
                return
            }
        }

        // 转换为JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData) else {
            completion(.failure(WorkCompletionError.jsonEncoding))
            return
        }

        // 创建URL请求
        guard let url = URL(string: apiEndpoint) else {
            completion(.failure(WorkCompletionError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 如果需要认证，添加认证头
        if needsAuth {
            request.setValue("Bearer \(appId)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = jsonData

        // 执行网络请求
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                // 检查HTTP响应状态
                if let httpResponse = response as? HTTPURLResponse {
                    guard 200...299 ~= httpResponse.statusCode else {
                        completion(.failure(WorkCompletionError.serverError(httpResponse.statusCode)))
                        return
                    }
                }

                // 这里可以解析响应数据（如果服务器返回数据）
                completion(.success(()))
            }
        }

        task.resume()
    }

    // 本地存储功能 - 作为备用方案
    func saveWorkCompletionLocally(_ data: WorkCompletionRecord) {
        let userDefaults = UserDefaults.standard
        var savedCompletions = userDefaults.array(forKey: "SavedWorkCompletions") as? [[String: Any]] ?? []

        let completionDict: [String: Any] = [
            "description": data.description,
            "tags": data.tags,
            "start_time": ISO8601DateFormatter().string(from: data.startTime),
            "end_time": ISO8601DateFormatter().string(from: data.endTime)
        ]

        savedCompletions.append(completionDict)

        // 保留最近100条记录
        if savedCompletions.count > 100 {
            savedCompletions = Array(savedCompletions.suffix(100))
        }

        userDefaults.set(savedCompletions, forKey: "SavedWorkCompletions")
    }

    // 简单的数据传输对象，用于本地存储
    struct WorkCompletionRecord {
        let description: String
        let tags: [String]
        let startTime: Date
        let endTime: Date
    }

    // 生成签名（HMAC-SHA256）
    private func generateSignature(for data: [String: Any], secret: String) -> String? {
        do {
            // 按字母顺序排序参数
            let sortedKeys = data.keys.sorted()
            var queryString = ""

            for key in sortedKeys {
                if key != "signature" { // 不对签名本身进行签名
                    let value = data[key]
                    if let stringValue = value as? String {
                        if !queryString.isEmpty {
                            queryString += "&"
                        }
                        queryString += "\(key)=\(stringValue)"
                    }
                }
            }

            // 使用HMAC-SHA256生成签名
            let key = secret.data(using: .utf8)!
            let data = queryString.data(using: .utf8)!

            let digest = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
            let signature = Data(digest).base64EncodedString()

            return signature
        } catch {
            print("签名生成失败: \(error)")
            return nil
        }
    }

    // 获取本地保存的完成记录
    func getLocalWorkCompletions() -> [WorkCompletionRecord] {
        let userDefaults = UserDefaults.standard
        guard let savedCompletions = userDefaults.array(forKey: "SavedWorkCompletions") as? [[String: Any]] else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        return savedCompletions.compactMap { dict in
            guard let description = dict["description"] as? String,
                  let tags = dict["tags"] as? [String],
                  let startTimeString = dict["start_time"] as? String,
                  let endTimeString = dict["end_time"] as? String,
                  let startTime = formatter.date(from: startTimeString),
                  let endTime = formatter.date(from: endTimeString) else {
                return nil
            }

            return WorkCompletionRecord(description: description, tags: tags, startTime: startTime, endTime: endTime)
        }.sorted { $0.endTime > $1.endTime }
    }
}

enum WorkCompletionError: Error, LocalizedError {
    case jsonEncoding
    case invalidURL
    case serverError(Int)
    case noEndpointConfigured
    case missingAuthCredentials
    case signatureGenerationFailed

    var errorDescription: String? {
        switch self {
        case .jsonEncoding:
            return "无法编码数据"
        case .invalidURL:
            return "无效的API地址"
        case .serverError(let code):
            return "服务器错误: \(code)"
        case .noEndpointConfigured:
            return "未配置API地址，数据已保存到本地"
        case .missingAuthCredentials:
            return "缺少认证凭据（App ID和App Secret都需要配置）"
        case .signatureGenerationFailed:
            return "签名生成失败"
        }
    }
}

// 设置API端点的公共方法
extension WorkCompletionService {
    func setAPIEndpoint(_ endpoint: String) {
        UserDefaults.standard.set(endpoint, forKey: "WorkCompletionAPIEndpoint")
    }

    func getAPIEndpoint() -> String {
        return apiEndpoint
    }
}

// WorkCompletionData 定义在 Timer.swift 中，这里不需要重复定义