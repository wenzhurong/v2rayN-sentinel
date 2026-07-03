import ServiceManagement

/// 用现代 SMAppService 管理"登录时启动"。需在打包后的 .app 内生效。
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
