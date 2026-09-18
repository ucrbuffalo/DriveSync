import Foundation

@objc protocol DriveSyncUninstallHelperProtocol {
    func verifyAvailability(
        reply: @escaping (Bool) -> Void
    )

    func removeDriveSyncApplication(
        reply: @escaping (Bool, String?) -> Void
    )

    func finishUninstall(
        reply: @escaping (Bool, String?) -> Void
    )
}
