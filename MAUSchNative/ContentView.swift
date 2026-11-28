import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let mauschURL = URL(string: "https://ppt0320.github.io/mausch/")!
private let mauschBackground = Color(red: 12.0 / 255.0, green: 12.0 / 255.0, blue: 11.0 / 255.0)
private let mauschGold = Color(red: 0.87, green: 0.74, blue: 0.58)

struct ContentView: View {
    @State private var webView: WKWebView?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            WebAppView(
                webView: $webView,
                isLoading: $isLoading,
                loadFailed: $loadFailed,
                onPageLoaded: { _ in }
            )
            .background(mauschBackground)

            if isLoading {
                ProgressView("Cargando MAU$…")
                    .tint(mauschGold)
                    .padding(18)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }

            if loadFailed {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34))
                        .foregroundStyle(mauschGold)
                    Text("No se pudo conectar")
                        .font(.title3.bold())
                    Text("Revisa tu conexión. Tus cajas, ventas e inventario guardados no se borraron.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))
                    Button("Intentar de nuevo") {
                        loadFailed = false
                        isLoading = true
                        webView?.reload()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(mauschGold)
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.08))
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background(Color(red: 0.10, green: 0.095, blue: 0.085), in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .background(mauschBackground.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

#if os(iOS)
private struct WebAppView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool
    let onPageLoaded: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadFailed: $loadFailed, onPageLoaded: onPageLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: "mauschBackup")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 12.0 / 255.0, green: 12.0 / 255.0, blue: 11.0 / 255.0, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.allowsBackForwardNavigationGestures = true
        webView = view
        view.load(URLRequest(url: mauschURL, cachePolicy: .useProtocolCachePolicy))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        @Binding private var isLoading: Bool
        @Binding private var loadFailed: Bool
        private let onPageLoaded: (WKWebView) -> Void

        init(isLoading: Binding<Bool>, loadFailed: Binding<Bool>, onPageLoaded: @escaping (WKWebView) -> Void) {
            _isLoading = isLoading
            _loadFailed = loadFailed
            self.onPageLoaded = onPageLoaded
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            loadFailed = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            loadFailed = false
            webView.evaluateJavaScript("""
            window.backup = async function() {
              try {
                for (let attempt = 0; attempt < 40; attempt++) {
                  if (typeof all === 'function' && typeof db !== 'undefined' && db) break;
                  await new Promise(resolve => setTimeout(resolve, 250));
                }
                if (typeof all !== 'function' || !db) throw new Error('El almacenamiento todavía se está cargando.');
                const file = {app: 'MAU$ch', version: 2, exportedAt: new Date().toISOString(), boxes: await all('boxes'), items: await all('moves')};
                window.webkit.messageHandlers.mauschBackup.postMessage(JSON.stringify(file));
              } catch (error) {
                alert(error.message || 'No se pudo preparar el respaldo.');
              }
            };
            """)
            onPageLoaded(webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mauschBackup",
                  let json = message.body as? String,
                  let data = json.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  payload["app"] as? String == "MAU$ch",
                  payload["version"] as? Int == 2 else {
                showBackupError("No se pudo preparar el archivo de respaldo.", in: message.webView)
                return
            }
            let date = DateFormatter()
            date.locale = Locale(identifier: "en_US_POSIX")
            date.dateFormat = "yyyyMMdd-HHmmss"
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("MAU$-Respaldo-\(date.string(from: Date())).json")
            do {
                try data.write(to: fileURL, options: .atomic)
                DispatchQueue.main.async { [weak self] in
                    guard let self, let webView = message.webView,
                          let presenter = self.topViewController(for: webView) else { return }
                    let share = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                    share.completionWithItemsHandler = { _, _, _, _ in
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    if let popover = share.popoverPresentationController {
                        popover.sourceView = presenter.view
                        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    presenter.present(share, animated: true)
                }
            } catch {
                showBackupError("No se pudo crear el archivo de respaldo.", in: message.webView)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let presenter = topViewController(for: webView) else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: "MAU$", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler() })
            presenter.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let presenter = topViewController(for: webView) else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: "MAU$", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "Continuar", style: .default) { _ in completionHandler(true) })
            presenter.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let presenter = topViewController(for: webView) else {
                completionHandler(nil)
                return
            }
            let alert = UIAlertController(title: "MAU$", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            presenter.present(alert, animated: true)
        }

        private func topViewController(for webView: WKWebView) -> UIViewController? {
            guard var presenter = webView.window?.rootViewController else { return nil }
            while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
                presenter = presented
            }
            return presenter
        }

        private func finish(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            isLoading = false
            loadFailed = true
        }

        private func showBackupError(_ text: String, in webView: WKWebView?) {
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, let presenter = self.topViewController(for: webView) else { return }
                let alert = UIAlertController(title: "MAU$", message: text, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Aceptar", style: .default))
                presenter.present(alert, animated: true)
            }
        }
    }
}
#elseif os(macOS)
private struct WebAppView: NSViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool
    let onPageLoaded: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadFailed: $loadFailed, onPageLoaded: onPageLoaded)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        webView = view
        view.load(URLRequest(url: mauschURL, cachePolicy: .useProtocolCachePolicy))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding private var isLoading: Bool
        @Binding private var loadFailed: Bool
        private let onPageLoaded: (WKWebView) -> Void

        init(isLoading: Binding<Bool>, loadFailed: Binding<Bool>, onPageLoaded: @escaping (WKWebView) -> Void) {
            _isLoading = isLoading
            _loadFailed = loadFailed
            self.onPageLoaded = onPageLoaded
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            loadFailed = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            loadFailed = false
            onPageLoaded(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let window = webView.window else {
                completionHandler()
                return
            }
            let alert = NSAlert()
            alert.messageText = "MAU$"
            alert.informativeText = message
            alert.addButton(withTitle: "Aceptar")
            alert.beginSheetModal(for: window) { _ in completionHandler() }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let window = webView.window else {
                completionHandler(false)
                return
            }
            let alert = NSAlert()
            alert.messageText = "MAU$"
            alert.informativeText = message
            alert.addButton(withTitle: "Cancelar")
            alert.addButton(withTitle: "Continuar")
            alert.buttons.first?.keyEquivalent = "\u{1b}"
            alert.buttons.last?.keyEquivalent = "\r"
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertSecondButtonReturn)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let window = webView.window else {
                completionHandler(nil)
                return
            }
            let alert = NSAlert()
            alert.messageText = "MAU$"
            alert.informativeText = prompt
            let input = NSTextField(string: defaultText ?? "")
            input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = input
            alert.addButton(withTitle: "Cancelar")
            alert.addButton(withTitle: "Aceptar")
            alert.buttons.first?.keyEquivalent = "\u{1b}"
            alert.buttons.last?.keyEquivalent = "\r"
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertSecondButtonReturn ? input.stringValue : nil)
            }
        }

        private func finish(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            isLoading = false
            loadFailed = true
        }
    }
}
#endif

