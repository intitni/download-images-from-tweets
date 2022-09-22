import AVFoundation
import Foundation
import WebKit

struct TweetImageDownloader {
    struct UnHandleableContent {
        let videos: [URL]
    }
    
    func downloadImages(
        fromTweetURL tweetURL: URL,
        intoDirectory directoryURL: URL,
        index: Int
    ) async throws -> UnHandleableContent {
        let (imageLinks, videoLinks) = try await getImageLinks(from: tweetURL)
        print("[\(index)] Found \(imageLinks.count) images, \(videoLinks.count) videos from \(tweetURL).")
        
        if imageLinks.isEmpty, videoLinks.isEmpty {
            print("[\(index)] Skip tweet \(tweetURL)")
            return .init(videos: [])
        }

        defer { print("✅ [\(index)] Finished downloading from \(tweetURL)") }
        return try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for resource in imageLinks {
                let url = resource.url(for: .large)
                taskGroup.addTask {
                    let (fileURL, format) = try await downloadImage(from: url)
                    try moveFile(
                        atURL: fileURL,
                        toDirectoryURL: directoryURL,
                        name: resource.name,
                        format: format
                    )
                }
            }
            try await taskGroup.waitForAll()
            return .init(videos: videoLinks.map(\.url))
        }
    }

    func getImageLinks(from url: URL) async throws -> Resource {
        return try await ResourceFetcher().fetch(url: url)
    }

    func downloadImage(from url: URL) async throws -> (url: URL, format: String) {
        let request = URLRequest(url: url)
        let result = try await URLSession.shared.download(for: request)
        return (result.0, result.1.mimeType.flatMap { mimeTypes[$0] } ?? "jpg")
    }

    func moveFile(
        atURL fileURL: URL,
        toDirectoryURL directoryURL: URL,
        name: String,
        format: String
    ) throws {
        let targetURL = targetFileURL(
            original: fileURL,
            toDirectoryURL: directoryURL,
            name: name,
            format: format
        )
        try FileManager.default.moveItem(at: fileURL, to: targetURL)
    }
}

func targetFileURL(
    original _: URL,
    toDirectoryURL directoryURL: URL,
    name: String,
    format: String
) -> URL {
    let targetURL = directoryURL
        .appendingPathComponent(name)
        .appendingPathExtension(format)
    return targetURL
}
