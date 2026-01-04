//
//  PersonaScheduler.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/1/4.
//

import AppKit
import Combine
import Foundation
import SwiftUI

struct Persona: Codable {
    let id: Int
    let userId: Int?
    let name: String
    let description: String?
    let icon: String
    let iconSvg: String?
    let content: String
    let isExample: Bool
    let createdAt: Int?
    let updatedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case description
        case icon
        case iconSvg = "icon_svg"
        case content
        case isExample = "is_example"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

class PersonaScheduler {
    static let shared = PersonaScheduler()

    @Published var personas: [Persona] = []

    private init() {
        reloadPersonasFromDatabase()
    }

    func checkAndFetchIfNeeded() {
        guard personas.isEmpty else {
            return
        }
        fetchPersonas()
    }

    func reloadPersonasFromDatabase() {
        do {
            personas = try DatabaseService.shared.getAllPersonas()
        } catch {
            log.error("人设加载失败: \(error)")
        }
    }

    private func fetchPersonas() {
        Task {
            guard JWTValidator.isValid(Config.shared.USER_CONFIG.authToken) else {
                return
            }
            await syncPersonas()
        }
    }

    private func syncPersonas() async {
        do {
            let response = try await HTTPClient.shared.post(
                path: "/custom-prompt/list",
                body: [:]
            )

            if let personasArray = response.dataArray {
                personas = personasArray.compactMap { dict -> Persona? in
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                          let persona = try? JSONDecoder().decode(Persona.self, from: jsonData)
                    else {
                        return nil
                    }
                    return persona
                }

                try DatabaseService.shared.savePersonas(personas)
                log.info("成功同步 \(personas.count) 个人设")
            }
        } catch {
            log.error("同步人设失败: \(error)")
        }
    }

    /// 设置全局 Persona
    /// - Parameter personaId: persona 的 ID
    func setPersona(personaId: Int?) {
        let persona: Persona? = personaId == nil ? nil : personas.first { $0.id == personaId }
        Config.shared.CURRENT_PERSONA = persona
        log.info("🎭 Persona 已设置: \(persona?.name ?? "默认")")
    }

    /// 通过索引设置全局 Persona
    /// - Parameter index: personas 数组的索引 (0-8 对应数字键 1-9)
    func setPersona(index: Int) {
        guard index < personas.count else {
            log.warning("Persona 索引超出范围: \(index + 1), 可用数量: \(personas.count)")
            Tooltip.show(content: "切换输出模式失败, 未设置对应模式", type: .error)
            return
        }

        setPersona(personaId: personas[index].id)

        Task { @MainActor in
            let persona = personas[index]
            var customIcon: NSImage?
            if let svgString = persona.iconSvg,
               let svgData = svgString.data(using: .utf8)
            {
                customIcon = NSImage(data: svgData)
            }

            let content = AnyView(
                HStack(spacing: 0) {
                    Text("已切换到")
                    Text(persona.name).foregroundColor(.overlayPrimary)
                    Text("输出模式")
                }
                .font(.system(size: 12))
                .foregroundColor(.overlayText)
            )

            Tooltip.show(customContent: content, type: .plain, showBell: false, customIcon: customIcon)
        }
    }
}
