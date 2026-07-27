import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the bundled Vite application from a stable origin.
///
/// A custom scheme avoids the inconsistent module, fetch, and storage behavior
/// that WKWebView can exhibit when an application is loaded from a `file:` URL.
final class BundledWebSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "dayman-app"

    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let requestURL = urlSchemeTask.request.url,
            requestURL.scheme == Self.scheme,
            requestURL.host == "app",
            let fileURL = bundledFileURL(for: requestURL)
        else {
            urlSchemeTask.didFailWithError(
                NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorBadURL,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid DayMan resource URL."]
                )
            )
            return
        }

        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType(for: fileURL),
                expectedContentLength: data.count,
                textEncodingName: textEncoding(for: fileURL)
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func bundledFileURL(for requestURL: URL) -> URL? {
        guard let decodedPath = requestURL.path.removingPercentEncoding else { return nil }
        let requestedPath = decodedPath.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        let relativePath = requestedPath.isEmpty ? "index.html" : requestedPath

        let candidate = rootURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPath), !candidate.hasDirectoryPath else { return nil }
        return candidate
    }

    private func mimeType(for fileURL: URL) -> String {
        UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }

    private func textEncoding(for fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "css", "html", "js", "json", "svg":
            return "utf-8"
        default:
            return nil
        }
    }
}
