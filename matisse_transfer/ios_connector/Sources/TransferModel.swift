import CryptoKit
import Foundation
import Photos

struct BridgeManifest: Decodable {
    let version: Int
    let items: [BridgeItem]
}

struct BridgeItem: Decodable, Identifiable {
    let id: String
    let category: String
    let filename: String
    let bytes: Int64
    let sha256: String
    let url: String
    let createdAt: Date?
}

struct TransferResult: Identifiable {
    let id = UUID()
    let text: String
    let success: Bool
}

@MainActor
final class TransferModel: ObservableObject {
    @Published var baseURL = ""
    @Published var status = "Inserisci l'indirizzo mostrato da Matisse sul PC."
    @Published var results: [TransferResult] = []
    @Published var running = false
    private var importedHashes = Set(UserDefaults.standard.stringArray(forKey: "matisse.imported.sha256") ?? [])

    func receive() async {
        guard let base = URL(string: baseURL), base.scheme == "http", base.host != nil else {
            status = "Indirizzo locale non valido."
            return
        }
        guard isPrivateLanHost(base.host!) else {
            status = "Per proteggere i file, Matisse accetta solo un indirizzo della rete locale."
            return
        }
        running = true
        results = []
        defer { running = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: base.appendingPathComponent("manifest"))
            try check(response)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(BridgeManifest.self, from: data)
            guard manifest.version == 1 else { throw BridgeError.invalidManifest }
            status = "Ricevo \(manifest.items.count) elementi selezionati…"
            for item in manifest.items {
                try Task.checkCancellation()
                let url = base.appendingPathComponent("files").appendingPathComponent(item.id)
                let (temporaryURL, fileResponse) = try await URLSession.shared.download(from: url)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                try check(fileResponse)
                let safeName = URL(fileURLWithPath: item.filename).lastPathComponent
                let stagedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent(safeName)
                try FileManager.default.createDirectory(at: stagedURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: temporaryURL, to: stagedURL)
                defer { try? FileManager.default.removeItem(at: stagedURL.deletingLastPathComponent()) }
                try verify(stagedURL, item: item)
                let importKey = item.category + ":" + item.sha256.lowercased()
                if importedHashes.contains(importKey) {
                    results.append(TransferResult(text: "\(item.filename) gia presente nel registro Matisse", success: true))
                    continue
                }
                try await importItem(stagedURL, item: item)
                importedHashes.insert(importKey)
                UserDefaults.standard.set(Array(importedHashes), forKey: "matisse.imported.sha256")
                results.append(TransferResult(text: "\(item.filename) aggiunto", success: true))
            }
            status = "Trasferimento completato."
        } catch {
            status = "Trasferimento interrotto: \(error.localizedDescription)"
        }
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BridgeError.httpFailure
        }
    }

    private func isPrivateLanHost(_ host: String) -> Bool {
        let name = host.lowercased()
        if name == "localhost" || name.hasSuffix(".local") { return true }
        let octets = name.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        return octets[0] == 10 || octets[0] == 127 || octets[0] == 169 && octets[1] == 254
            || octets[0] == 192 && octets[1] == 168
            || octets[0] == 172 && (16...31).contains(octets[1])
    }

    private func verify(_ url: URL, item: BridgeItem) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) == item.bytes else { throw BridgeError.sizeMismatch(item.filename) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == item.sha256.lowercased() else { throw BridgeError.hashMismatch(item.filename) }
    }

    private func importItem(_ source: URL, item: BridgeItem) async throws {
        switch item.category {
        case "foto", "video":
            try await addToPhotos(source, item: item)
        case "documenti", "musica":
            try saveToFiles(source, filename: item.filename)
        default:
            throw BridgeError.unsupportedCategory(item.category)
        }
    }

    private func addToPhotos(_ source: URL, item: BridgeItem) async throws {
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else { throw BridgeError.photoPermission }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = item.createdAt
                let type: PHAssetResourceType = item.category == "video" ? .video : .photo
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = item.filename
                request.addResource(with: type, fileURL: source, options: options)
            } completionHandler: { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? BridgeError.photoImportFailed) }
            }
        }
    }

    private func saveToFiles(_ source: URL, filename: String) throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeName = URL(fileURLWithPath: filename).lastPathComponent
        var target = documents.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: target.path) {
            let stem = target.deletingPathExtension().lastPathComponent
            let ext = target.pathExtension
            target = documents.appendingPathComponent("\(stem)_\(UUID().uuidString.prefix(8)).\(ext)")
        }
        try FileManager.default.copyItem(at: source, to: target)
    }
}

enum BridgeError: LocalizedError {
    case invalidManifest, httpFailure, photoPermission, photoImportFailed
    case sizeMismatch(String), hashMismatch(String), unsupportedCategory(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "Formato del pacchetto non supportato."
        case .httpFailure: return "Il PC non ha restituito il file richiesto."
        case .photoPermission: return "Autorizzazione Foto non concessa."
        case .photoImportFailed: return "Foto non ha completato l'importazione."
        case .sizeMismatch(let name): return "Dimensione non corretta: \(name)"
        case .hashMismatch(let name): return "Controllo integrità non riuscito: \(name)"
        case .unsupportedCategory(let name): return "Categoria non supportata: \(name)"
        }
    }
}
