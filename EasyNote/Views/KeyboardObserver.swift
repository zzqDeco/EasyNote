import Combine
import UIKit

final class KeyboardObserver: ObservableObject {
    @Published private(set) var keyboardHeight: CGFloat = 0
    @Published private(set) var isKeyboardVisible = false

    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    var registrationCount: Int {
        cancellables.count
    }

    func start() {
        guard cancellables.isEmpty else { return }

        notificationCenter.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return
                }
                self?.keyboardHeight = keyboardFrame.height
                self?.isKeyboardVisible = true
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                self?.keyboardHeight = 0
                self?.isKeyboardVisible = false
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        keyboardHeight = 0
        isKeyboardVisible = false
    }
}
