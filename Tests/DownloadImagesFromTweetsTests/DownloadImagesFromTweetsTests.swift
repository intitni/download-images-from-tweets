@testable import DownloadImagesFromTweets
import XCTest

let content = """
// From Twitter Archive
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
// In CSV format
https://t.co/UlTuJpr9EA,https://twitter.com/kgtdesuteni/status/1574353093092790272,最近のヌコまとめ
"""

final class DownloadImagesFromTweetsTests: XCTestCase {
    func testGetTweetLinksFromContent() throws {
        XCTAssertEqual(getLinks(from: content), [
            URL(string: "https://twitter.com/i/web/status/1572149111780179969")!,
            URL(string: "https://twitter.com/i/web/status/1571801944511123460")!,
            URL(string: "https://twitter.com/kgtdesuteni/status/1574353093092790272")
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
        XCTAssertEqual(resources.videos.count, 0)
        XCTAssertEqual(resources.images[0].urlComponents.host, "pbs.twimg.com")
    }
    
    func testDownloaderGetLinksFromRandomWebSiteShouldFail() async throws {
        let downloader = TweetImageDownloader()
        do {
            _ = try await downloader.getImageLinks(from: URL(string: "https://markinside.intii.com/")!)
        } catch is FailToLoadTweetError {
            XCTAssert(true)
        } catch {
            XCTFail()
        }
    }
    
    func testDownloaderGetLinksFromTweetsWithNoMedia() async throws {
        let downloader = TweetImageDownloader()
        let resources = try await downloader.getImageLinks(from: URL(string: "https://twitter.com/intitni/status/1477157643236130817")!)
        XCTAssertEqual(resources.images.count, 0)
        XCTAssertEqual(resources.videos.count, 0)
    }
}
