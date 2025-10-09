import Foundation
import CryptoKit

// 默认API端点常量
private let DEFAULT_API_ENDPOINT = "https://tomast.narro.cn/api/v1/pomodoros"

internal class WorkCompletionService {
    static let shared = WorkCompletionService()

    private init() {}

    // 从用户配置中获取API端点，默认为 DEFAULT_API_ENDPOINT
    private var apiEndpoint: String {
        return UserDefaults.standard.string(forKey: "WorkCompletionAPIEndpoint") ?? DEFAULT_API_ENDPOINT
    }

    // 获取App ID
    private var appId: String {
        return UserDefaults.standard.string(forKey: "WorkCompletionAppId") ?? ""
    }

    // 获取App Secret
    private var appSecret: String {
        return UserDefaults.standard.string(forKey: "WorkCompletionAppSecret") ?? ""
    }

    internal func uploadWorkCompletion(_ data: WorkCompletionRecord, completion: @escaping (Result<Void, Error>) -> Void) {
        // 检查是否配置了API端点
        guard !apiEndpoint.isEmpty else {
            completion(.failure(WorkCompletionError.noEndpointConfigured))
            return
        }

        // 检查是否配置了App ID和App Secret
        guard !appId.isEmpty, !appSecret.isEmpty else {
            completion(.failure(WorkCompletionError.missingAuthCredentials))
            return
        }

        // 创建时间戳
        let timestamp = String(Int(Date().timeIntervalSince1970))

        // 创建基础数据结构，匹配API要求的格式
        let requestData: [String: Any] = [
            "client": "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "description": data.description,
            "end_time": ISO8601DateFormatter().string(from: data.endTime),
            "source": "TomatoBar App",
            "start_time": ISO8601DateFormatter().string(from: data.startTime)
        ]

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

        // 生成签名
        guard let signature = generateSignature(for: request, appId: appId, timestamp: timestamp, secret: appSecret) else {
            completion(.failure(WorkCompletionError.signatureGenerationFailed))
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
    internal struct WorkCompletionRecord {
        let description: String
        let tags: [String]
        let startTime: Date
        let endTime: Date
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

        // 获取查询参数并排序
        var queryParams = [String: String]()
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                if let value = item.value {
                    queryParams[item.name] = value
                }
            }
        }

        // 移除签名相关的参数
        queryParams.removeValue(forKey: "signature")
        queryParams.removeValue(forKey: "api_key")
        queryParams.removeValue(forKey: "timestamp")
        queryParams.removeValue(forKey: "app_id")

        // 构建查询字符串
        let sortedKeys = queryParams.keys.sorted()
        var queryStringParts = [String]()
        for key in sortedKeys {
            if let value = queryParams[key],
               let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                queryStringParts.append("\(key)=\(encodedValue)")
            }
        }
        let queryString = queryStringParts.joined(separator: "&")

        // 构建签名字符串
        // 格式: METHOD\nPATH\nQUERY_STRING\nTIMESTAMP\nAPI_KEY
        let signingString = "\(method)\n\(path)\n\(queryString)\n\(timestamp)\n\(appId)"

        // 使用HMAC-SHA256生成签名
        guard let keyData = secret.data(using: .utf8),
              let stringData = signingString.data(using: .utf8) else {
            return nil
        }

        let digest = HMAC<SHA256>.authenticationCode(for: stringData, using: SymmetricKey(data: keyData))
        let signature = Data(digest).hexEncodedString()

        return signature
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