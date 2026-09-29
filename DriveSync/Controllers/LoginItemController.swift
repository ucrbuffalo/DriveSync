import Foundation
import ServiceManagement

final class DriveSyncLoginItemController {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    // Add or remove DriveSync from the user's Login Items.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }

    // Open the pane where a blocked login item can be approved.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
