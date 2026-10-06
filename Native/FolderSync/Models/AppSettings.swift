import Foundation

struct AppSettings: Codable, Hashable {
    var waitsForFileOperations: Bool

    init(waitsForFileOperations: Bool = true) {
        self.waitsForFileOperations = waitsForFileOperations
    }

    private enum CodingKeys: String, CodingKey {
        case waitsForFileOperations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waitsForFileOperations = try container.decodeIfPresent(Bool.self, forKey: .waitsForFileOperations) ?? true
    }
}
