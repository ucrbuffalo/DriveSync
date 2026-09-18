import Foundation

final class UninstallHelperClient {
    private let machServiceName = "com.drivesync.uninstall-helper"

    func verifyAvailability(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let connection = NSXPCConnection(
            machServiceName: machServiceName,
            options: .privileged
        )

        connection.remoteObjectInterface = NSXPCInterface(
            with: DriveSyncUninstallHelperProtocol.self
        )

        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            connection.invalidate()

            DispatchQueue.main.async {
                completion(
                    .failure(
                        UninstallHelperClientError.helperFailure(
                            "DriveSync couldn't start the uninstaller service. No changes were made. Please try again."
                        )
                    )
                )
            }
        }) as? DriveSyncUninstallHelperProtocol else {
            connection.invalidate()

            DispatchQueue.main.async {
                completion(.failure(UninstallHelperClientError.invalidProxy))
            }
            return
        }

        proxy.verifyAvailability { available in
            connection.invalidate()

            DispatchQueue.main.async {
                if available {
                    completion(.success(()))
                } else {
                    completion(
                        .failure(
                            UninstallHelperClientError.helperFailure(
                                "DriveSync could not access the privileged uninstall helper. No changes were made."
                            )
                        )
                    )
                }
            }
        }
    }

    func verifyAvailability() async throws {
        try await withCheckedThrowingContinuation { continuation in
            verifyAvailability { result in
                continuation.resume(with: result)
            }
        }
    }

    func removeDriveSyncApplication(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let connection = NSXPCConnection(
            machServiceName: machServiceName,
            options: .privileged
        )

        connection.remoteObjectInterface = NSXPCInterface(
            with: DriveSyncUninstallHelperProtocol.self
        )

        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            connection.invalidate()

            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }) as? DriveSyncUninstallHelperProtocol else {
            connection.invalidate()

            DispatchQueue.main.async {
                completion(.failure(UninstallHelperClientError.invalidProxy))
            }
            return
        }

        proxy.removeDriveSyncApplication { success, message in
            connection.invalidate()

            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    completion(
                        .failure(
                            UninstallHelperClientError.helperFailure(
                                message ?? "DriveSync.app could not be removed."
                            )
                        )
                    )
                }
            }
        }
    }

    func removeDriveSyncApplication() async throws {
        try await withCheckedThrowingContinuation { continuation in
            removeDriveSyncApplication { result in
                continuation.resume(with: result)
            }
        }
    }

    func finishUninstall(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let connection = NSXPCConnection(
            machServiceName: machServiceName,
            options: .privileged
        )

        connection.remoteObjectInterface = NSXPCInterface(
            with: DriveSyncUninstallHelperProtocol.self
        )

        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            connection.invalidate()

            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }) as? DriveSyncUninstallHelperProtocol else {
            connection.invalidate()

            DispatchQueue.main.async {
                completion(.failure(UninstallHelperClientError.invalidProxy))
            }
            return
        }

        proxy.finishUninstall { success, message in
            connection.invalidate()

            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    completion(
                        .failure(
                            UninstallHelperClientError.helperFailure(
                                message ?? "DriveSync could not complete final cleanup."
                            )
                        )
                    )
                }
            }
        }
    }

    func finishUninstall() async throws {
        try await withCheckedThrowingContinuation { continuation in
            finishUninstall { result in
                continuation.resume(with: result)
            }
        }
    }
}

enum UninstallHelperClientError: LocalizedError {
    case invalidProxy
    case helperFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidProxy:
            return "DriveSync could not communicate with the uninstall helper."

        case .helperFailure(let message):
            return message
        }
    }
}
