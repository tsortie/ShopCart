import SwiftUI
import CloudKit

struct CloudSharingView: UIViewControllerRepresentable {
    let list: GroceryList
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            Task {
                do {
                    let (share, container) = try await CloudKitManager.shared.createShare(for: list)
                    completion(share, container, nil)
                } catch {
                    completion(nil, CloudKitManager.shared.container, error)
                }
            }
        }
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        @Binding var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Share error: \(error)")
            isPresented = false
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            isPresented = false
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            isPresented = false
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            return "ShopCart List"
        }
    }
}
