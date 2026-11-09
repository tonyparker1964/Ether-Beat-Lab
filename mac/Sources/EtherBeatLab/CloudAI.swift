import Foundation
import Security

/// Optional online AI for the AI Producer: Claude (Anthropic) or OpenAI, with your own API key.
/// The key is kept in your Mac's Keychain. Only the producer's text request (your vibe and the names of the
/// sounds it can choose from) is sent; no audio or other files leave your Mac.
enum CloudAI {
    static let service = "com.ether.beatlab.ai"

    // MARK: Keychain

    static func key(_ provider: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: provider, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setKey(_ provider: String, _ value: String?) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: provider]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    // MARK: Requests

    static func ask(provider: String, system: String, user: String, model: String) async -> [String: String] {
        let name = provider == "claude" ? "Claude" : "OpenAI"
        guard let apiKey = key(provider), !apiKey.isEmpty else {
            return ["error": "Add your \(name) API key in AI settings first."]
        }
        var req: URLRequest
        let chosen = model.isEmpty ? (provider == "claude" ? "claude-sonnet-5-5" : "gpt-5.5") : model
        if provider == "claude" {
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": chosen, "max_tokens": 2000, "system": system,
                "messages": [["role": "user", "content": user]]
            ] as [String: Any])
        } else {
            req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": chosen,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]]
            ] as [String: Any])
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (200..<300).contains(status) else {
                let msg = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
                let hint = status == 401 ? " Check the API key." : status == 404 ? " Check the model name." : status == 429 ? " You've hit a rate or spending limit." : ""
                return ["error": "\(name) answered with an error (\(status)).\(hint) \(msg.prefix(160))"]
            }
            var text = ""
            if provider == "claude" {
                text = ((obj?["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
            } else {
                text = (((obj?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ["error": "\(name) answered with nothing."] }
            return ["text": text, "model": (obj?["model"] as? String) ?? chosen]
        } catch {
            return ["error": "Couldn't reach \(name). Check your internet connection. (\(error.localizedDescription))"]
        }
    }

    /// The models your key can use, newest first as the provider lists them.
    static func models(provider: String) async -> [String] {
        guard let apiKey = key(provider), !apiKey.isEmpty else { return [] }
        var req = URLRequest(url: URL(string: provider == "claude" ? "https://api.anthropic.com/v1/models?limit=100" : "https://api.openai.com/v1/models")!)
        if provider == "claude" { req.setValue(apiKey, forHTTPHeaderField: "x-api-key"); req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version") }
        else { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        guard let result = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let items = obj["data"] as? [[String: Any]] else { return [] }
        var ids = items.compactMap { $0["id"] as? String }
        if provider == "openai" {
            // only chat models
            let skip = ["audio", "realtime", "transcribe", "tts", "image", "search"]
            ids = ids.filter { id in id.hasPrefix("gpt-") && !skip.contains { id.contains($0) } }.sorted(by: >)
        }
        return ids
    }

    /// Bridge actions. Returns false when the action isn't one of these.
    static func handle(_ action: String, _ body: [String: Any], reply: @escaping (Any?, String?) -> Void) -> Bool {
        let provider = (body["provider"] as? String) == "openai" ? "openai" : "claude"
        switch action {
        case "aiKeyStatus":
            reply(Engine.jsonString(["claude": key("claude") != nil, "openai": key("openai") != nil]), nil)
        case "aiSetKey":
            let ok = setKey(provider, (body["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            let out: [String: Any] = ok ? ["ok": true] : ["error": "The key couldn't be saved in the Keychain."]
            reply(Engine.jsonString(out), nil)
        case "aiModels":
            Task { let list = await models(provider: provider); await MainActor.run { reply(Engine.jsonString(list), nil) } }
        case "setLocalServer":
            let url = (body["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if url.isEmpty { UserDefaults.standard.removeObject(forKey: "lmStudioURL") } else { UserDefaults.standard.set(url, forKey: "lmStudioURL") }
            reply(Engine.jsonString(["url": Producer.baseURL]), nil)
        case "localModels":
            Task {
                var ids: [String] = []
                if let url = URL(string: Producer.baseURL + "/v1/models"),
                   let result = try? await URLSession.shared.data(from: url),
                   let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
                   let items = obj["data"] as? [[String: Any]] {
                    ids = items.compactMap { $0["id"] as? String }.filter { !$0.lowercased().contains("embed") }
                }
                let out: [String: Any] = ["url": Producer.baseURL, "models": ids, "reachable": !ids.isEmpty]
                await MainActor.run { reply(Engine.jsonString(out), nil) }
            }
        case "aiProduce":
            Task {
                let r = await ask(provider: provider, system: body["system"] as? String ?? "", user: body["user"] as? String ?? "",
                                  model: (body["model"] as? String ?? "").trimmingCharacters(in: .whitespaces))
                await MainActor.run { reply(Engine.jsonString(r), nil) }
            }
        default:
            return false
        }
        return true
    }
}
