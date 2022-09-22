@testable import DownloadImagesFromTweets
import XCTest

let content = """
{
  "like" : {
    "tweetId" : "1572149111780179969",
    "fullText" : "【生徒紹介・スキル編】\n「梅花園」の教官を務めるココナさんは、味方1人と自身のHPを回復するEXスキルを持ちます。またEXスキル等で獲得できる「花丸スタンプ」は、5個集める度に味方のスキルコストを1度減少させることが可能です！\n\n■PROFILE\n春原ココナ\nMIDDLE・ヒーラー\nCV:#五十嵐裕美\n#ブルアカ https://t.co/DYJIE3Y0zi",
    "expandedUrl" : "https://twitter.com/i/web/status/1572149111780179969"
  }
},
{
  "like" : {
    "tweetId" : "1571801944511123460",
    "fullText" : "☁️\n#シナモンミク https://t.co/akfe6ytCl4",
    "expandedUrl" : "https://twitter.com/i/web/status/1571801944511123460"
  }
},
{
  "like" : {
    "tweetId" : "1572164917666488320",
    "fullText" : "秋の匂いがするね https://t.co/m92pjBvPk6",
    "expandedUrl" : "https://twitter.com/i/web/status/1572164917666488320"
  }
}
"""

final class DownloadImagesFromTweetsTests: XCTestCase {
    func testGetTweetLinksFromContent() throws {
        XCTAssertEqual(getLinks(from: content), [
            URL(string: "https://twitter.com/i/web/status/1572149111780179969")!,
            URL(string: "https://twitter.com/i/web/status/1571801944511123460")!,
            URL(string: "https://twitter.com/i/web/status/1572164917666488320")!,
        ])
    }

    func testImageResourceParsingAndGettingURLForSize() {
        let resource = ImageResource(urlString: "https://pbs.twimg.com/media/FWJ8YmYaAAEjJzZ?format=jpg&name=medium")
        XCTAssertNotNil(resource)
        let r = resource!
        XCTAssertEqual(r.name, "FWJ8YmYaAAEjJzZ")
        let resizedURL = r.url(for: .large)
        XCTAssertTrue(resizedURL.absoluteString.contains("name=large"))
    }

    func testTargetFileURLGeneration() {
        XCTAssertEqual(
            "/path/to/file/name.jpg",
            targetFileURL(
                original: URL(fileURLWithPath: "/tmp/randomName.tmp"),
                toDirectoryURL: URL(fileURLWithPath: "/path/to/file"),
                name: "name",
                format: "jpg"
            ).path
        )
    }
}

/// These tests are going to fire up real network requests.
final class RealWorldTests: XCTestCase {
    func testDownloaderGetLinks() async throws {
        let downloader = TweetImageDownloader()
        let resources = try await downloader.getImageLinks(from: URL(string: "https://twitter.com/intitni/status/1567150754191769606")!)
        XCTAssertEqual(resources.images.count, 1)
        XCTAssertEqual(resources.images[0].urlComponents.host, "pbs.twimg.com")
    }
}
