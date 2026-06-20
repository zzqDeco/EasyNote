import Foundation

enum CloudKitPreflightSeverity: String, Equatable {
    case passed
    case warning
    case blocked
}

struct CloudKitPreflightCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let remediation: String
    let severity: CloudKitPreflightSeverity
}

struct CloudKitPreflightReport: Equatable {
    let containerIdentifier: String
    let checks: [CloudKitPreflightCheck]

    var blockingChecks: [CloudKitPreflightCheck] {
        checks.filter { $0.severity == .blocked }
    }

    var warningChecks: [CloudKitPreflightCheck] {
        checks.filter { $0.severity == .warning }
    }

    var isReadyForRealSync: Bool {
        blockingChecks.isEmpty
    }

    var overallSeverity: CloudKitPreflightSeverity {
        if !blockingChecks.isEmpty {
            return .blocked
        }

        if !warningChecks.isEmpty {
            return .warning
        }

        return .passed
    }

    var summary: String {
        switch overallSeverity {
        case .passed:
            return "预检通过，可以进入真实 CloudKit enablement PR"
        case .warning:
            return "存在非阻塞注意项，真实同步仍需人工验证"
        case .blocked:
            return "真实 iCloud 同步仍被阻塞，当前保持本地优先"
        }
    }

    func check(withID id: String) -> CloudKitPreflightCheck? {
        checks.first { $0.id == id }
    }
}

enum CloudKitSyncPreflight {
    static let defaultContainerIdentifier = "iCloud.io.github.zzqDeco.EasyNote"

    struct Configuration: Equatable {
        var expectedContainerIdentifier: String
        var serviceContainerIdentifier: String
        var entitlementContainerIdentifiers: [String]
        var hasCloudKitServiceEntitlement: Bool
        var debugSimulationMode: Bool
        var swiftDataAutomaticSyncEnabled: Bool
        var schemaIsDeployed: Bool
        var conflictPolicyIsDocumented: Bool
        var recordIdentityRoundTripIsImplemented: Bool
        var manualValidationIsComplete: Bool

        static var currentProject: Configuration {
            #if DEBUG
            let debugSimulationMode = true
            #else
            let debugSimulationMode = false
            #endif

            return Configuration(
                expectedContainerIdentifier: CloudKitSyncPreflight.defaultContainerIdentifier,
                serviceContainerIdentifier: CloudKitSyncPreflight.defaultContainerIdentifier,
                entitlementContainerIdentifiers: [],
                hasCloudKitServiceEntitlement: false,
                debugSimulationMode: debugSimulationMode,
                swiftDataAutomaticSyncEnabled: false,
                schemaIsDeployed: false,
                conflictPolicyIsDocumented: true,
                recordIdentityRoundTripIsImplemented: false,
                manualValidationIsComplete: false
            )
        }
    }

    static func currentProjectReport() -> CloudKitPreflightReport {
        evaluate(Configuration.currentProject)
    }

    static func evaluate(_ configuration: Configuration) -> CloudKitPreflightReport {
        let expectedContainer = configuration.expectedContainerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let serviceContainer = configuration.serviceContainerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        let checks: [CloudKitPreflightCheck] = [
            containerIdentifierCheck(expected: expectedContainer, actual: serviceContainer),
            entitlementCheck(configuration: configuration, serviceContainer: serviceContainer),
            debugModeCheck(configuration: configuration),
            swiftDataBoundaryCheck(configuration: configuration),
            schemaDeploymentCheck(configuration: configuration),
            conflictPolicyCheck(configuration: configuration),
            recordIdentityCheck(configuration: configuration),
            manualValidationCheck(configuration: configuration)
        ]

        return CloudKitPreflightReport(
            containerIdentifier: serviceContainer,
            checks: checks
        )
    }

    private static func containerIdentifierCheck(expected: String, actual: String) -> CloudKitPreflightCheck {
        if actual.isEmpty {
            return CloudKitPreflightCheck(
                id: "container-id",
                title: "CloudKit container ID",
                detail: "未配置 CloudKit container identifier。",
                remediation: "在 CloudKitService 和 entitlements 中使用固定容器 \(expected)。",
                severity: .blocked
            )
        }

        if actual != expected {
            return CloudKitPreflightCheck(
                id: "container-id",
                title: "CloudKit container ID",
                detail: "当前容器 \(actual) 与预期 \(expected) 不一致。",
                remediation: "统一 service、entitlements、CloudKit Dashboard 中的 container ID。",
                severity: .blocked
            )
        }

        return CloudKitPreflightCheck(
            id: "container-id",
            title: "CloudKit container ID",
            detail: "当前容器为 \(actual)。",
            remediation: "保持 service 和 entitlements 使用同一容器。",
            severity: .passed
        )
    }

    private static func entitlementCheck(configuration: Configuration, serviceContainer: String) -> CloudKitPreflightCheck {
        let hasContainer = configuration.entitlementContainerIdentifiers.contains(serviceContainer)
        if configuration.hasCloudKitServiceEntitlement && hasContainer {
            return CloudKitPreflightCheck(
                id: "icloud-entitlement",
                title: "iCloud entitlement",
                detail: "CloudKit service 和目标容器 entitlement 已配置。",
                remediation: "保持 Debug/Release signing 配置一致。",
                severity: .passed
            )
        }

        return CloudKitPreflightCheck(
            id: "icloud-entitlement",
            title: "iCloud entitlement",
            detail: "当前 entitlements 未完整声明 CloudKit service 和目标容器。",
            remediation: "启用真实同步前添加 iCloud services=CloudKit，并声明 \(serviceContainer)。",
            severity: .blocked
        )
    }

    private static func debugModeCheck(configuration: Configuration) -> CloudKitPreflightCheck {
        if configuration.debugSimulationMode {
            return CloudKitPreflightCheck(
                id: "debug-simulation",
                title: "Debug simulation mode",
                detail: "Debug 构建仍强制使用 CloudKit 模拟模式。",
                remediation: "真实同步 PR 需要提供显式开关，并在 Release 或手动验证构建中关闭模拟模式。",
                severity: .blocked
            )
        }

        return CloudKitPreflightCheck(
            id: "debug-simulation",
            title: "Debug simulation mode",
            detail: "当前配置不会强制进入模拟模式。",
            remediation: "保留测试/预览路径的本地模拟能力。",
            severity: .passed
        )
    }

    private static func swiftDataBoundaryCheck(configuration: Configuration) -> CloudKitPreflightCheck {
        if configuration.swiftDataAutomaticSyncEnabled {
            return CloudKitPreflightCheck(
                id: "swiftdata-boundary",
                title: "SwiftData sync boundary",
                detail: "SwiftData automatic CloudKit sync 已启用。",
                remediation: "如果改用 SwiftData 自动同步，需要迁移计划覆盖 ModelConfiguration、schema 和冲突策略。",
                severity: .warning
            )
        }

        return CloudKitPreflightCheck(
            id: "swiftdata-boundary",
            title: "SwiftData sync boundary",
            detail: "SwiftData ModelContainer 保持本地 `.none`，CloudKitService 是云同步边界。",
            remediation: "除非另开迁移计划，否则不要同时启用 SwiftData automatic sync 和手写 CloudKit sync。",
            severity: .passed
        )
    }

    private static func schemaDeploymentCheck(configuration: Configuration) -> CloudKitPreflightCheck {
        if configuration.schemaIsDeployed {
            return CloudKitPreflightCheck(
                id: "schema-deployment",
                title: "CloudKit schema",
                detail: "CloudKit schema 已按当前记录契约部署。",
                remediation: "schema 变更必须同步更新 docs 和手动验证步骤。",
                severity: .passed
            )
        }

        return CloudKitPreflightCheck(
            id: "schema-deployment",
            title: "CloudKit schema",
            detail: "CloudKit Dashboard schema 尚未部署并验证。",
            remediation: "启用前部署 DiaryEntry 和 AudioRecording 记录类型及字段契约。",
            severity: .blocked
        )
    }

    private static func conflictPolicyCheck(configuration: Configuration) -> CloudKitPreflightCheck {
        if configuration.conflictPolicyIsDocumented {
            return CloudKitPreflightCheck(
                id: "conflict-policy",
                title: "Conflict strategy",
                detail: "冲突策略已记录为 stable id + lastModified 优先的合并边界。",
                remediation: "真实同步 PR 必须用测试或手动双设备流程验证该策略。",
                severity: .passed
            )
        }

        return CloudKitPreflightCheck(
            id: "conflict-policy",
            title: "Conflict strategy",
            detail: "冲突策略尚未定义。",
            remediation: "启用前明确同一 DiaryEntry 在多设备编辑时的合并/覆盖规则。",
            severity: .blocked
        )
    }

    private static func recordIdentityCheck(configuration: Configuration) -> CloudKitPreflightCheck {
        if configuration.recordIdentityRoundTripIsImplemented {
            return CloudKitPreflightCheck(
                id: "record-identity",
                title: "Record identity round trip",
                detail: "CloudKit recordName 与本地 UUID 可以双向保持一致。",
                remediation: "继续用 DiaryEntry.id.uuidString 作为 CloudKit recordName。",
                severity: .passed
            )
        }

        return CloudKitPreflightCheck(
            id: "record-identity",
            title: "Record identity round trip",
            detail: "当前 fetch 路径尚未证明会保留 CloudKit recordName 对应的本地 UUID。",
            remediation: "真实同步 PR 需要让下载记录恢复原始 DiaryEntry.id，并覆盖相应测试。",
            severity: .blocked
        )
    }

    private static func manualValidationCheck(configuration: Configuration) -> CloudKitPreflightCheck {
        if configuration.manualValidationIsComplete {
            return CloudKitPreflightCheck(
                id: "manual-validation",
                title: "Manual validation",
                detail: "真实设备/账号手动验证已完成。",
                remediation: "把验证结果写入对应 PR body，而不是新增长期台账。",
                severity: .passed
            )
        }

        return CloudKitPreflightCheck(
            id: "manual-validation",
            title: "Manual validation",
            detail: "尚未在真实 iCloud 账号和兼容设备上完成同步验证。",
            remediation: "启用前验证登录状态、上传、下载、冲突、离线失败和恢复路径。",
            severity: .blocked
        )
    }
}
