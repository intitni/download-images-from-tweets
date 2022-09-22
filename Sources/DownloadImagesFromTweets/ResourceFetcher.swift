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

final class ResourceFetcher: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Resource, Error>?
    private var webView: WKWebView
    private let jsHandler = JSHandler()
    @MainActor private var retryCount = -1
    private let retryLimit: Int
    private var didFindArticle = false
    
    @MainActor
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
        webView.configuration.userContentController.add(jsHandler, name: "jsListener")
        jsHandler.didFindURLs = { [weak self] urls in
            self?.handleURLStrings(urls)
        }
        jsHandler.wasLoading = { [weak self] in
            Task {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                self?.checkResource()
            }
        }
    }

    @MainActor
    func fetch(url: URL) async throws -> Resource {
        retryCount = -1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            _ = self.webView.load(.init(url: url))
        }
    }

    @MainActor
    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        webView.evaluateJavaScript(preloadScript)
        checkResource()
    }

    /// Find image links from the web source.
    ///
    /// Since it's hard to determine if the webpage is fully loaded, it will retry
    /// several times to see if images exist in this tweet. If no tweets found after retries,
    /// it will consider that this tweet has no image.
    @MainActor
    func checkResource() {
        retryCount += 1
        guard retryCount <= retryLimit else {
            if didFindArticle {
                continuation?.resume(returning: (images: [], videos: []))
            } else {
                struct E: Error, LocalizedError {
                    var errorDescription: String? { "Failed to load tweet." }
                }
                self.continuation?.resume(throwing: E())
            }
            return
        }
        webView.evaluateJavaScript(findSrcFromImgElements) { value, error in
            if let error {
                self.continuation?.resume(throwing: error)
            }
        }
    }
    
    func handleURLStrings(_ urlStrings: [String]) {
        didFindArticle = true
        let srcs = urlStrings
        let images = srcs.compactMap { ImageResource(urlString: $0) }
        let videos = srcs.compactMap { VideoResource(urlString: $0) }
        if images.isEmpty && videos.isEmpty {
            Task.detached {
                try await Task.sleep(nanoseconds: 500_000_000)
                await self.checkResource()
            }
        } else {
            self.continuation?.resume(returning: (images: images, videos: videos))
        }
    }
}

final class JSHandler: NSObject, WKScriptMessageHandler {
    var didFindURLs: ([String]) -> Void = { _ in }
    var wasLoading: () -> Void = {}
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            let urlString = message.body as? String,
            let data = urlString.data(using: .utf8),
            let urls = try? JSONDecoder().decode([String].self, from: data)
        else {
            wasLoading()
            return
        }
        didFindURLs(urls)
    }
}

private let preloadScript = """
window.postM = (message) => {
    if (window.webkit) {
        window.webkit.messageHandlers.jsListener.postMessage(message);
    } else {
        console.info(message);
    }
}
"""

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
    window.postM(JSON.stringify(window.urls));
} else {
    window.postM("loading");
}
"""
