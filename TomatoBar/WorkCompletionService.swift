import Foundation

class WorkCompletionService {
    static let shared = WorkCompletionService()

    private init() {}

    // 从用户配置中获取API端点，默认为空字符串（不上传）
    private var apiEndpoint: String {
        return UserDefaults.standard.string(forKey: "WorkCompletionAPIEndpoint") ?? ""
    }

    func uploadWorkCompletion(_ data: WorkCompletionRecord, completion: @escaping (Result<Void, Error>) -> Void) {
        // 检查是否配置了API端点
        guard !apiEndpoint.isEmpty else {
            completion(.failure(WorkCompletionError.noEndpointConfigured))
            return
        }

        // 创建请求的数据结构
        let requestData: [String: Any] = [
            "description": data.description,
            "tags": data.tags,
            "timestamp": ISO8601DateFormatter().string(from: data.timestamp),
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
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
            "timestamp": ISO8601DateFormatter().string(from: data.timestamp)
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
        let timestamp: Date
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
                  let timestampString = dict["timestamp"] as? String,
                  let timestamp = formatter.date(from: timestampString) else {
                return nil
            }

            return WorkCompletionRecord(description: description, tags: tags, timestamp: timestamp)
        }.sorted { $0.timestamp > $1.timestamp }
    }
}

enum WorkCompletionError: Error, LocalizedError {
    case jsonEncoding
    case invalidURL
    case serverError(Int)
    case noEndpointConfigured

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