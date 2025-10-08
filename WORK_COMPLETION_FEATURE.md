# 番茄钟完成记录功能

## 功能概述

这个功能允许用户在完成每个番茄钟后记录他们的工作内容，并可以选择将数据上传到自定义服务器。

## 使用方法

1. **完成番茄钟**：当一个番茄钟（工作时间）完成时，会自动弹出一个记录窗口
2. **填写内容**：
   - 工作内容：描述在这个番茄钟中完成的工作
   - 标签：添加相关标签，用逗号分隔
3. **选择操作**：
   - **提交**：保存记录并尝试上传到配置的API端点
   - **跳过**：不保存任何内容，直接关闭窗口
   - **取消**：关闭窗口，不进行任何操作

## API 配置

### 设置端点

在应用设置的"API配置"部分输入你的服务器配置：
- **API端点**：留空则数据只保存在本地，输入URL则尝试上传到指定地址
- **应用ID**：用于API认证的应用标识符
- **应用密钥**：用于生成HMAC-SHA256签名的密钥（请保密）

### API 规范

你的API端点需要接受POST请求，Content-Type为application/json。

#### 请求数据格式

**基础请求（无认证）：**
```json
{
  "client": "macOS 13.0",
  "description": "完成了项目文档的编写",
  "end_time": "2023-12-01T10:25:00Z",
  "source": "TomatoBar App",
  "start_time": "2023-12-01T10:00:00Z"
}
```

**认证请求（带签名）：**
```json
{
  "client": "macOS 13.0",
  "description": "完成了项目文档的编写",
  "end_time": "2023-12-01T10:25:00Z",
  "source": "TomatoBar App",
  "start_time": "2023-12-01T10:00:00Z",
  "app_id": "your-app-id",
  "signature": "base64编码的HMAC-SHA256签名"
}
```

**请求头：**
- `Content-Type: application/json`
- `Authorization: Bearer your-app-id`（认证请求时）

#### 响应格式
- 成功：HTTP状态码 200-299
- 失败：其他状态码或网络错误

### 签名验证

为了确保请求的安全性，应用使用HMAC-SHA256算法对请求进行签名：

1. **参数排序**：按字母顺序排列所有请求参数（除了signature本身）
2. **查询字符串**：将参数拼接成 `key1=value1&key2=value2` 格式
3. **生成签名**：使用App Secret作为密钥，对查询字符串进行HMAC-SHA256计算
4. **Base64编码**：将签名结果进行Base64编码

**服务器端验证示例：**
```javascript
// Node.js示例
const crypto = require('crypto');

function verifySignature(data, appSecret) {
    const { signature, ...params } = data;
    const sortedKeys = Object.keys(params).sort();
    const queryString = sortedKeys.map(key => `${key}=${params[key]}`).join('&');

    const expectedSignature = crypto
        .createHmac('sha256', appSecret)
        .update(queryString)
        .digest('base64');

    return signature === expectedSignature;
}
```

### 错误处理

如果上传失败，数据会自动保存在本地。可能的错误包括：

- **未配置API地址**：数据只保存到本地
- **缺少认证凭据**：App ID和App Secret都需要配置
- **签名生成失败**：通常是内部错误
- **网络或服务器错误**：数据保存到本地备用

你可以通过以下方式访问本地数据：

```swift
// 获取本地保存的记录
let completions = WorkCompletionService.shared.getLocalWorkCompletions()
```

## 本地数据存储

所有记录（包括上传成功的）都会保存在本地UserDefaults中，最多保留100条记录。数据以JSON格式存储，包含：
- 工作描述
- 标签列表
- 工作开始时间
- 工作结束时间

### 数据结构

**Swift结构体：**
```swift
struct WorkCompletionData {
    let description: String
    let tags: [String]
    let startTime: Date
    let endTime: Date
}
```

**本地存储格式：**
```json
{
  "description": "完成了项目文档的编写",
  "tags": ["文档", "项目", "写作"],
  "start_time": "2023-12-01T10:00:00Z",
  "end_time": "2023-12-01T10:25:00Z"
}
```

## 隐私说明

- 工作记录仅保存在本地设备上
- 只有配置了API端点时才会尝试上传数据
- 所有网络请求都通过HTTPS进行
- 用户可以随时清空本地数据

## 开发者说明

### 添加新功能

要扩展工作记录功能，可以修改以下文件：
- `WorkCompletionView.swift`：修改UI界面
- `WorkCompletionService.swift`：修改数据上传逻辑
- `Timer.swift`：修改触发时机

### 自定义字段

要添加新的记录字段，需要：
1. 修改 `WorkCompletionData` 结构
2. 更新 `WorkCompletionView` 界面
3. 修改 `WorkCompletionService` 中的数据格式化逻辑

### 测试

测试模式下的数据不会真正上传，只会模拟网络请求延迟。要测试完整功能，需要：
1. 配置一个测试API端点
2. 运行完整的番茄钟流程
3. 验证数据是否正确上传