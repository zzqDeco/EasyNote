import Foundation

struct PersistenceFeedback: Equatable {
    let shouldDismiss: Bool
    let errorMessage: String?

    static func resolve(
        succeeded: Bool,
        viewModelError: String?,
        fallbackError: String
    ) -> PersistenceFeedback {
        if succeeded {
            return PersistenceFeedback(shouldDismiss: true, errorMessage: nil)
        }

        return PersistenceFeedback(
            shouldDismiss: false,
            errorMessage: viewModelError ?? fallbackError
        )
    }
}
