import Foundation
import WebKit

/// Image links are like https://pbs.twimg.com/media/FWJ8YmYaAAEjJzZ?format=jpg&name=medium
struct ImageResource {
    let name: String
    let urlComponents: URLComponents

    enum Size: String {
        case medium
        case large
    }

    init?(urlString: String) {
        guard urlString.hasPrefix("https://pbs.twimg.com/media/") else { return nil }
        guard var components = URLComponents(string: urlString) else { return nil }
        if components.queryItems == nil {
            components.queryItems = []
        }
        components.queryItems?.removeAll(where: { $0.name == "name" })
        urlComponents = components
        name = components.url?.lastPathComponent ?? UUID().uuidString
    }

    func url(for size: Size) -> URL {
        var components = urlComponents
        components.queryItems?.append(URLQueryItem(name: "name", value: size.rawValue))
        return components.url!
    }
}

/// Video links are like https://video.twimg.com/ext_tw_video/1572148907916034050/pu/pl/ciBX1Fuam0OswkZA.m3u8?variant_version=1&tag=12&container=fmp4
struct VideoResource {
    let name: String
    let url: URL

    init?(urlString: String) {
        guard
            urlString.hasPrefix("https://video.twimg.com"),
            let url = URL(string: urlString)
        else { return nil }
        self.url = url
        name = UUID().uuidString
    }
}

typealias Resource = (images: [ImageResource], videos: [VideoResource])

@MainActor
final class ResourceFetcher: NSObject, WKNavigationDelegate {
    var webView: WKWebView

    let retryLimit: Int
    var webViewDidFinishLoading = false
    var webViewError: (any Error)?

    init(retryLimit: Int = 10) {
        self.retryLimit = retryLimit
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Avoid blob video links being used!
        configuration.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15"
        // The web page need the web view to have a size to load correctly.
        let webView = WKWebView(
            frame: .init(x: 0, y: 0, width: 500, height: 500),
            configuration: configuration
        )
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func fetch(url: URL) async throws -> Resource {
        webViewDidFinishLoading = false
        webViewError = nil
        var retryCount = 0
        var isLoading = true
        _ = webView.load(.init(url: url))
        while !webViewDidFinishLoading {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let error = webViewError {
                throw error
            }
        }
        while retryCount < retryLimit {
            retryCount += 1
            
            guard let srcs = try await findSrcFromHTMLContent() else {
                try await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            isLoading = false

            let images = srcs.compactMap { ImageResource(urlString: $0) }
            let videos = srcs.compactMap { VideoResource(urlString: $0) }
            if images.isEmpty, videos.isEmpty {
                try await Task.sleep(nanoseconds: 300_000_000)
            } else {
                return (images: images, videos: videos)
            }
        }
        
        if isLoading {
            throw FailToLoadTweetError()
        } else {
            return (images: [], videos: [])
        }
    }

    nonisolated func webView(_: WKWebView, didFinish _: WKNavigation!) {
        Task { @MainActor in
            self.webViewDidFinishLoading = true
        }
    }

    nonisolated func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.webViewError = error
            self.webViewDidFinishLoading = true
        }
    }

    func findSrcFromHTMLContent() async throws -> [String]? {
        return try await webView.evaluateJavaScript(findSrcFromImgElements) as? [String]
    }
}

struct FailToLoadTweetError: Error, LocalizedError {
    var errorDescription: String? { "Failed to load tweet." }
}

/// Find the first `<article/>` in document, if found, return all `img` `src`.
private let findSrcFromImgElements = """
window.foundArticle = document.getElementsByTagName("article")[0];
if (window.foundArticle) {
    window.foundArticle.scrollIntoView();
    window.imgs = window.foundArticle.getElementsByTagName("img");
    window.videos = window.foundArticle.getElementsByTagName("video");
    window.urls = [];
    for (const img of window.imgs) {
        const src = img.getAttribute("src");
        if (src) {
          window.urls.push(src);
        }
    }
    for (const video of window.videos) {
        const src = video.getAttribute("src");
        if (src) {
            window.urls.push(src);
        }
    }
    window.urls;
} else {
    "loading"
}
"""
