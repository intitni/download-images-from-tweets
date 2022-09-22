# Download Images From Tweets

It's a tool used to download images from tweets without Twitter API.

It will open the tweet page in a hidden web view, glance through the web content, find the links, and download them.

Since `WKWebView` is used, it will only work on macOS.

## Usage

```
USAGE: the_program [--file <file>] [--url <url>] --output <output>

OPTIONS:
  --file <file>           A text file that contains URLs to tweets.
  --url <url>             A link of tweet
  -o, --output <output>   The path of output folder
  -h, --help              Show help information.
```

You can build it yourself or download a built version from the latest GitHub Action workflow artifacts.

## Videos

I tried, but it's not that easy and out of scope. The program will also generate a text file containing all detected video m3u8 links. Please use another tool to download them.
