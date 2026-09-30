import Foundation

/// A file in the site's media library, as the upload returned it.
struct UploadedMedia: Equatable {
    var id: String
    var url: String
    var width: Int?
    var height: Int?
}

extension EmDashClient {
    /// `POST /media` takes one multipart file. The site answers with an existing item when the bytes match one.
    func upload(_ file: PreparedImage) async throws -> UploadedMedia {
        let span = Pace.begin("request")
        defer { Pace.end(span, detail: "POST /media \(file.data.count) bytes") }
        let boundary = "emd-\(UUID().uuidString)"
        var request = URLRequest(url: SiteURL.endpoint(site: site, path: "/media"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = Self.multipart(file, boundary: boundary)
        let (data, response) = try await session.upload(for: request, from: body)
        let json = try Self.decoded(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        return try Self.media(from: json)
    }

    static func multipart(_ file: PreparedImage, boundary: String) -> Data {
        let name = file.filename.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\r\n", with: " ")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".utf8))
        body.append(Data("Content-Type: \(file.mimeType)\r\n\r\n".utf8))
        body.append(file.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    static func media(from json: JSONValue) throws -> UploadedMedia {
        guard let item = json.object?["item"]?.object, let id = item["id"]?.string, let url = item["url"]?.string
        else {
            throw APIError(status: 500, code: "BAD_RESPONSE", message: "The site did not return the uploaded image.")
        }
        return UploadedMedia(
            id: id,
            url: url,
            width: item["width"]?.number.map { Int($0) },
            height: item["height"]?.number.map { Int($0) }
        )
    }
}
