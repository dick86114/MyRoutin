import Foundation

enum TransferSchemaCodec {
    static func encode(_ package: TransferPackageV1) throws -> Data {
        guard package.schemaVersion == 1 else { throw TransferSchemaError.unsupportedVersion(package.schemaVersion) }
        try package.credentials.forEach { try $0.validate() }
        let credentialIDs = Set(package.credentials.map(\.credentialId))
        guard package.secretEnvelope.entries.allSatisfy({ credentialIDs.contains($0.credentialId) }) else {
            throw TransferSchemaError.invalidEnvelope("credentialAssociation")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(package)
    }

    static func decode(_ data: Data) throws -> TransferPackageV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TransferPackageV1.self, from: data)
    }
}
