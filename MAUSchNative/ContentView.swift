import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let mauschURL = URL(string: "https://ppt0320.github.io/mausch/")!

struct ContentView: View {
    @State private var webView: WKWebView?
    @State private var isLoading = true
    @State private var loadFailed = false

    private let background = Color(red: 11.0 / 255.0, green: 18.0 / 255.0, blue: 32.0 / 255.0)

    var body: some View {
        ZStack {
            WebAppView(
                webView: $webView,
                isLoading: $isLoading,
                loadFailed: $loadFailed
            )

            if isLoading {
                ProgressView("Cargando MAU$ch…")
                    .tint(.white)
                    .padding(16)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("mausch.loading")
            }

            if loadFailed {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("No se pudo conectar")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Revisa tu conexión e inténtalo de nuevo. Tus datos guardados en esta app no se borraron.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.75))
                    Button("Intentar de nuevo", action: reload)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 49.0 / 255.0, green: 211.0 / 255.0, blue: 154.0 / 255.0))
                        .accessibilityIdentifier("mausch.retry")
                }
                .padding(28)
                .frame(maxWidth: 380)
                .background(background)
                .accessibilityIdentifier("mausch.connectionError")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func reload() {
        loadFailed = false
        isLoading = true
        webView?.reload()
    }
}

#if os(iOS)
private struct WebAppView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadFailed: $loadFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Use the persistent website store. Never clear it during reload or recovery.
        configuration.websiteDataStore = .default()

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 11.0 / 255.0, green: 18.0 / 255.0, blue: 32.0 / 255.0, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.allowsBackForwardNavigationGestures = true
        webView = view
        view.load(URLRequest(url: mauschURL, cachePolicy: .useProtocolCachePolicy))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding private var isLoading: Bool
        @Binding private var loadFailed: Bool

        init(isLoading: Binding<Bool>, loadFailed: Binding<Bool>) {
            _isLoading = isLoading
            _loadFailed = loadFailed
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            loadFailed = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            loadFailed = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finishWith(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finishWith(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // WebKit can reclaim a backgrounded process. Reload without touching website data.
            webView.reload()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Handle target="_blank" links in the existing view instead of silently doing nothing.
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        private func finishWith(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            isLoading = false
            loadFailed = true
        }
    }
}
#elseif os(macOS)
private struct WebAppView: NSViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadFailed: $loadFailed)
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

        init(isLoading: Binding<Bool>, loadFailed: Binding<Bool>) {
            _isLoading = isLoading
            _loadFailed = loadFailed
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            loadFailed = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            loadFailed = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finishWith(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finishWith(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        private func finishWith(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            isLoading = false
            loadFailed = true
        }
    }
}
#endif
