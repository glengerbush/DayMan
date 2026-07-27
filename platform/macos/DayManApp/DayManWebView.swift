import AppKit
import SwiftUI
import WebKit

struct DayManWebView: NSViewRepresentable {
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(loadError: $loadError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: NativeBridge.channelName)
        controller.addUserScript(
            WKUserScript(
                source: """
                Object.defineProperty(window, "__DAYMAN_NATIVE__", {
                  value: Object.freeze({
                    platform: "macOS",
                    bridgeVersion: 1,
                    messageHandler: "daymanState"
                  }),
                  writable: false,
                  configurable: false
                });
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.loadApplication(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: NativeBridge.channelName
        )
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private var loadError: Binding<String?>
        private let bridge = NativeBridge()
        private var webRoot: URL?

        init(loadError: Binding<String?>) {
            self.loadError = loadError
        }

        func loadApplication(in webView: WKWebView) {
            guard
                let root = Bundle.main.resourceURL?.appendingPathComponent("Web", isDirectory: true),
                FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path)
            else {
                loadError.wrappedValue =
                    "The bundled web application is missing. Run scripts/sync-web-assets.sh before building."
                return
            }

            webRoot = root
            webView.loadFileURL(
                root.appendingPathComponent("index.html"),
                allowingReadAccessTo: root
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.frameInfo.isMainFrame else { return }

            do {
                try bridge.receive(message.body)
                evaluateBridgeResult(.success(()), in: message.webView)
            } catch {
                evaluateBridgeResult(.failure(error), in: message.webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.isFileURL, isInsideBundle(url) {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated,
               ["https", "http"].contains(url.scheme?.lowercased()) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            loadError.wrappedValue = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            loadError.wrappedValue = error.localizedDescription
        }

        private func isInsideBundle(_ url: URL) -> Bool {
            guard let webRoot else { return false }
            return url.standardizedFileURL.path.hasPrefix(
                webRoot.standardizedFileURL.path + "/"
            ) || url.standardizedFileURL == webRoot.standardizedFileURL
        }

        private func evaluateBridgeResult(
            _ result: Result<Void, Error>,
            in webView: WKWebView?
        ) {
            let detail: [String: Any]
            switch result {
            case .success:
                detail = ["ok": true]
            case .failure(let error):
                detail = ["ok": false, "error": error.localizedDescription]
            }

            guard
                let data = try? JSONSerialization.data(withJSONObject: detail),
                let json = String(data: data, encoding: .utf8)
            else { return }

            webView?.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('dayman:native-result',{detail:\(json)}));"
            )
        }
    }
}
