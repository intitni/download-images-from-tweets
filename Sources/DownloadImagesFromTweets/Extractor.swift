import ArgumentParser
import Foundation

@main
struct Extractor: AsyncParsableCommand {
    @Option(name: .long, help: "A text file that contains urls to tweets.")
    var file: String?
    @Option(name: .long, help: "A link of tweet")
    var url: String?
    @Option(name: .shortAndLong, help: "The path of output folder")
    var output: String

    mutating func run() async throws {
        let outputURL = output.expandedFileURL
        try checkAndCreateOutputDirectoryIfNeeded(at: outputURL)

        var urls = [URL]()
        if let file {
            urls = try readURLsFromFile(at: file.expandedFileURL)
        } else if let url {
            guard let url = URL(string: url) else { throw URLIncorrect() }
            urls.append(url)
        } else {
            throw ArgumentsRequired()
        }
        
        print("\(urls.count) tweet links found.")
        let (failedURLs, unhandledVideos) = await startDownload(from: urls, saveTo: outputURL)
        print("✅ Finished. \(failedURLs.count) failed.")
        
        if !failedURLs.isEmpty {
            let content = failedURLs.map { failedURL in
                "\(failedURL.url.absoluteString) [\(failedURL.localizedDescription)]"
            }.joined(separator: "\n").data(using: .utf8)
            let failedURLsPath = outputURL.appendingPathComponent("_failedURLs.txt").path
            FileManager.default.createFile(atPath: failedURLsPath, contents: content)
            print("See \(failedURLsPath) for tweet that failed.")
        }
        
        if !unhandledVideos.isEmpty {
            let content = unhandledVideos.compactMap { videoSet in
                if videoSet.videos.isEmpty { return nil }
                return "\(videoSet.tweetURL)\n\(videoSet.videos.map(\.absoluteString).joined(separator: "\n"))\n"
            }.joined(separator: "\n").data(using: .utf8)
            let unhandledVideosPath = outputURL.appendingPathComponent("_videos.txt").path
            FileManager.default.createFile(atPath: unhandledVideosPath, contents: content)
            print("See \(unhandledVideosPath) for videos' m3u8 links. You will need other tools to download them.")
        }
    }
    
    func startDownload(from urls: [URL], saveTo outputURL: URL) async -> ([FailedURL], [UnhandledVideos]) {
        let downloader = TweetImageDownloader()
        return await withTaskGroup(
            of: Result<UnhandledVideos, FailedURL>.self
        ) { taskGroup in
            var failedURLs = [FailedURL]()
            var unhandledVideos = [UnhandledVideos]()
            func handle(_ result: Result<UnhandledVideos, FailedURL>) {
                switch result {
                case let .success(content):
                    unhandledVideos.append(content)
                case let .failure(url):
                    failedURLs.append(url)
                }
            }
            for (index, url) in urls.enumerated() {
                if index > 5 { // at most 5 task at a time.
                    if let result = await taskGroup.next() {
                        handle(result)
                    }
                }
                taskGroup.addTask {
                    do {
                        let unhandledContent = try await downloader.downloadImages(
                            fromTweetURL: url,
                            intoDirectory: outputURL,
                            index: index
                        )
                        return .success(.init(tweetURL: url, videos: unhandledContent.videos))
                    } catch {
                        print("❌ [\(index)] \(error.localizedDescription)")
                        return .failure(.init(url: url, error: error))
                    }
                }
            }
            for await result in taskGroup {
                handle(result)
            }
            return (failedURLs, unhandledVideos)
        }
    }
}

func checkAndCreateOutputDirectoryIfNeeded(at outputURL: URL) throws {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDir)
    if !exists {
        print("Created output directory at \(outputURL.path).")
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: false
        )
    } else if !isDir.boolValue {
        throw OutputIsNotDirectory()
    }
}

func readURLsFromFile(at url: URL) throws -> [URL] {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    guard exists, !isDirectory.boolValue else { throw FileNotFound() }
    let data = try Data(contentsOf: url)
    let content = String(data: data, encoding: .utf8) ?? ""
    return getLinks(from: content)
}

func getLinks(from content: String) -> [URL] {
    let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let matches = detector.matches(
        in: content,
        options: [],
        range: NSRange(location: 0, length: content.utf16.count)
    )

    return matches.compactMap { match in
        guard let range = Range(match.range, in: content) else { return nil }
        let url = content[range]
        guard url.hasPrefix("https://twitter.com") else { return nil }
        return URL(string: String(url))
    }
}

extension String {
    var expandedFileURL: URL {
        return URL(fileURLWithPath: (self as NSString).expandingTildeInPath)
    }
}

struct FileNotFound: Error, LocalizedError {
    var errorDescription: String? {
        "File not found."
    }
}
struct OutputIsNotDirectory: Error, LocalizedError {
    var errorDescription: String? {
        "The output path is not a directory."
    }
}
struct ArgumentsRequired: Error, LocalizedError {
    var errorDescription: String? {
        "Either an tweet url or a file containing urls must be provided."
    }
}
struct URLIncorrect: Error, LocalizedError {
    var errorDescription: String? {
        "URL incorrect."
    }
}
struct FailedURL: Error {
    let url: URL
    var error: any Error
}
struct UnhandledVideos {
    let tweetURL: URL
    let videos: [URL]
}
