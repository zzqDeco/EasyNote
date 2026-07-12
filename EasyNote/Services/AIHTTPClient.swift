import Combine
import Foundation

protocol AIHTTPClientProviding {
    func dataTaskPublisher(
        for request: URLRequest
    ) -> AnyPublisher<(data: Data, response: URLResponse), URLError>
}

struct URLSessionAIHTTPClient: AIHTTPClientProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func dataTaskPublisher(
        for request: URLRequest
    ) -> AnyPublisher<(data: Data, response: URLResponse), URLError> {
        session.dataTaskPublisher(for: request)
            .map { (data: $0.data, response: $0.response) }
            .eraseToAnyPublisher()
    }
}
