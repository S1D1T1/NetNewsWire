//
//  DetailWebViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/11/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import AppKit
@preconcurrency import WebKit
import RSCore
import RSWeb
import Articles

protocol DetailWebViewControllerDelegate: AnyObject {
	func mouseDidEnter(_: DetailWebViewController, link: String)
	func mouseDidExit(_: DetailWebViewController)
}

final class DetailWebViewController: NSViewController {

	weak var delegate: DetailWebViewControllerDelegate?
	var webView: DetailWebView!
	var state: DetailState = .noSelection {
		didSet {
			if state != oldValue {
				switch state {
				case .article(_, let scrollY), .extracted(_, _, let scrollY):
					windowScrollY = scrollY
				default:
					break
				}
				reloadHTML()
			}
		}
	}
	
	var article: Article? {
		switch state {
		case .article(let article, _):
			return article
		case .extracted(let article, _, _):
			return article
		default:
			return nil
		}
	}
	
	private var articleTextSize = AppDefaults.shared.articleTextSize

	#if !MAC_APP_STORE
		private var webInspectorEnabled: Bool {
			get {
				return webView.configuration.preferences._developerExtrasEnabled
			}
			set {
				webView.configuration.preferences._developerExtrasEnabled = newValue
			}
		}
	#endif
	
	private let detailIconSchemeHandler = DetailIconSchemeHandler()
	private var waitingForFirstReload = false
	private let keyboardDelegate = DetailKeyboardDelegate()
	private var windowScrollY: CGFloat?

	private var isShowingExtractedArticle: Bool {
		switch state {
		case .extracted(_, _, _):
			return true
		default:
			return false
		}
	}

	static let userScripts: [WKUserScript] = {
		let filenames = ["main", "main_mac", "newsfoot"]
		let scripts = filenames.map { filename in
			let scriptURL = Bundle.main.url(forResource: filename, withExtension: ".js")!
			let scriptSource = try! String(contentsOf: scriptURL)
			return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
		}
		return scripts
	}()

	private struct MessageName {
		static let mouseDidEnter = "mouseDidEnter"
		static let mouseDidExit = "mouseDidExit"
		static let windowDidScroll = "windowDidScroll"
	}

	override func loadView() {
		let preferences = WKPreferences()
		preferences.minimumFontSize = 12.0
		preferences.javaScriptCanOpenWindowsAutomatically = false

		let configuration = WKWebViewConfiguration()
		configuration.preferences = preferences
		configuration.defaultWebpagePreferences.allowsContentJavaScript = AppDefaults.shared.isArticleContentJavascriptEnabled
		configuration.setURLSchemeHandler(detailIconSchemeHandler, forURLScheme: ArticleRenderer.imageIconScheme)
		configuration.mediaTypesRequiringUserActionForPlayback = .audio

		let userContentController = WKUserContentController()
		userContentController.add(self, name: MessageName.windowDidScroll)
		userContentController.add(self, name: MessageName.mouseDidEnter)
		userContentController.add(self, name: MessageName.mouseDidExit)
		for script in Self.userScripts {
			userContentController.addUserScript(script)
		}
		configuration.userContentController = userContentController

		webView = DetailWebView(frame: NSRect.zero, configuration: configuration)
		webView.uiDelegate = self
		webView.navigationDelegate = self
		webView.keyboardDelegate = keyboardDelegate
		webView.translatesAutoresizingMaskIntoConstraints = false
		if let userAgent = UserAgent.fromInfoPlist() {
			webView.customUserAgent = userAgent
		}

		view = webView

		// Use the safe area layout guides if they are available.
		if #available(OSX 11.0, *) {
			// These constraints have been removed as they were unsatisfiable after removing NSBox.
		} else {
			let constraints = [
				webView.topAnchor.constraint(equalTo: view.topAnchor),
				webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
				webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
				webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			]
			NSLayoutConstraint.activate(constraints)
		}

		// Hide the web view until the first reload (navigation) is complete (plus some delay) to avoid the awful white flash that happens on the initial display in dark mode.
		// See bug #901.
		webView.isHidden = true
		waitingForFirstReload = true

		#if !MAC_APP_STORE
			webInspectorEnabled = AppDefaults.shared.webInspectorEnabled
			NotificationCenter.default.addObserver(self, selector: #selector(webInspectorEnabledDidChange(_:)), name: .WebInspectorEnabledDidChange, object: nil)
		#endif

		NotificationCenter.default.addObserver(self, selector: #selector(webFeedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(avatarDidBecomeAvailable(_:)), name: .AvatarDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(currentArticleThemeDidChangeNotification(_:)), name: .CurrentArticleThemeDidChangeNotification, object: nil)

		webView.loadFileURL(ArticleRenderer.blank.url, allowingReadAccessTo: ArticleRenderer.blank.baseURL)
	}

	// MARK: Notifications
	
	@objc func webFeedIconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func avatarDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func faviconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}
	
	@objc func userDefaultsDidChange(_ note: Notification) {
		if articleTextSize != AppDefaults.shared.articleTextSize {
			articleTextSize = AppDefaults.shared.articleTextSize
			reloadHTMLMaintainingScrollPosition()
		}
	}
	
	@objc func currentArticleThemeDidChangeNotification(_ note: Notification) {
		reloadHTMLMaintainingScrollPosition()
	}
	
	// MARK: Media Functions
	
	func stopMediaPlayback() {
		webView.evaluateJavaScript("stopMediaPlayback();")
	}
	
	// MARK: Scrolling

	func canScrollDown(_ completion: @escaping (Bool) -> Void) {
		fetchScrollInfo { (scrollInfo) in
			completion(scrollInfo?.canScrollDown ?? false)
		}
	}

	func canScrollUp(_ completion: @escaping (Bool) -> Void) {
		fetchScrollInfo { (scrollInfo) in
			completion(scrollInfo?.canScrollUp ?? false)
		}
	}

	override func scrollPageDown(_ sender: Any?) {
		webView.scrollPageDown(sender)
	}

	override func scrollPageUp(_ sender: Any?) {
		webView.scrollPageUp(sender)
	}

	// MARK: State Restoration
	
	func saveState(to state: inout [AnyHashable : Any]) {
		state[UserInfoKey.isShowingExtractedArticle] = isShowingExtractedArticle
		state[UserInfoKey.articleWindowScrollY] = windowScrollY
	}
	
}

// MARK: - WKScriptMessageHandler

extension DetailWebViewController: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		if message.name == MessageName.windowDidScroll {
			windowScrollY = message.body as? CGFloat
		} else if message.name == MessageName.mouseDidEnter, let link = message.body as? String {
			delegate?.mouseDidEnter(self, link: link)
		} else if message.name == MessageName.mouseDidExit {
			delegate?.mouseDidExit(self)
		}
	}
}

// MARK: - WKNavigationDelegate & WKUIDelegate

extension DetailWebViewController: WKNavigationDelegate, WKUIDelegate {

	// Bottleneck through which WebView-based URL opens go
	func openInBrowser(_ url: URL, flags: NSEvent.ModifierFlags) {
		let invert = flags.contains(.shift) || flags.contains(.command)
		Browser.open(url.absoluteString, invertPreference: invert)
	}

	// WKNavigationDelegate

	public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
		if navigationAction.navigationType == .linkActivated {
			if let url = navigationAction.request.url {
				self.openInBrowser(url, flags: navigationAction.modifierFlags)
			}
			decisionHandler(.cancel)
			return
		}

		decisionHandler(.allow)
	}
	
	public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		// See note in viewDidLoad()
		if waitingForFirstReload {
			assert(webView.isHidden)
			waitingForFirstReload = false
			reloadHTML()

			// Waiting for the first navigation to complete isn't long enough to avoid the flash of white.
			// A hard coded value is awful, but 5/100th of a second seems to be enough.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
				webView.isHidden = false
			}
		} else {
			if let windowScrollY = windowScrollY {
				webView.evaluateJavaScript("window.scrollTo(0, \(windowScrollY));")
				self.windowScrollY = nil
			}
		}
	}

	// WKUIDelegate
	
	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		// This method is reached when WebKit handles a JavaScript based window.open() invocation, for example. One
		// example where this is used is in YouTube's embedded video player when a user clicks on the video's title
		// or on the "Watch in YouTube" button. For our purposes we'll handle such window.open calls the same way we
		// handle clicks on a URL.
		if let url = navigationAction.request.url {
			self.openInBrowser(url, flags: navigationAction.modifierFlags)
		}

		return nil
	}
}

// MARK: - Private

private extension DetailWebViewController {

	func reloadArticleImage() {
		guard let article = article else { return }
		
		var components = URLComponents()
		components.scheme = ArticleRenderer.imageIconScheme
		components.path = article.articleID
		
		if let imageSrc = components.string {
			webView?.evaluateJavaScript("reloadArticleImage(\"\(imageSrc)\")")
		}
	}
	
	func reloadHTMLMaintainingScrollPosition() {
		fetchScrollInfo() { scrollInfo in
			self.windowScrollY = scrollInfo?.offsetY
			self.reloadHTML()
		}
	}

	func reloadHTML() {
		delegate?.mouseDidExit(self)
		
		let theme = ArticleThemesManager.shared.currentTheme
		let rendering: ArticleRenderer.Rendering

		switch state {
		case .noSelection:
			rendering = ArticleRenderer.noSelectionHTML(theme: theme)
		case .multipleSelection:
			rendering = ArticleRenderer.multipleSelectionHTML(theme: theme)
		case .loading:
			rendering = ArticleRenderer.loadingHTML(theme: theme)
		case .article(let article, _):
			detailIconSchemeHandler.currentArticle = article

			/// S1D1T1: patch in here to show youtube video info
			if let articleURL = article.url,
			   YouTubeVideoInfo.isYouTubeVideo(articleURL) {
				let tmpRendering = ArticleRenderer.articleHTML(article: article, theme: theme)
				rendering = addYouTubeInfo(articleURL,tmpRendering)
			}
			else {
				rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
			}
			/// S1D1T1: end patch 

		case .extracted(let article, let extractedArticle, _):
			detailIconSchemeHandler.currentArticle = article
			rendering = ArticleRenderer.articleHTML(article: article, extractedArticle: extractedArticle, theme: theme)
		}
		
		let substitutions = [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"style": rendering.style,
			"body": rendering.html
		]
		
		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
		html = ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: rendering.baseURL, html: html)
		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}

	func fetchScrollInfo(_ completion: @escaping (ScrollInfo?) -> Void) {
		var javascriptString = "var x = {contentHeight: document.body.scrollHeight, offsetY: document.body.scrollTop}; x"
		if #available(macOS 10.15, *) {
			javascriptString = "var x = {contentHeight: document.body.scrollHeight, offsetY: window.pageYOffset}; x"
		}

		webView.evaluateJavaScript(javascriptString) { (info, error) in
			guard let info = info as? [String: Any] else {
				completion(nil)
				return
			}
			guard let contentHeight = info["contentHeight"] as? CGFloat, let offsetY = info["offsetY"] as? CGFloat else {
				completion(nil)
				return
			}

			let scrollInfo = ScrollInfo(contentHeight: contentHeight, viewHeight: self.webView.frame.height, offsetY: offsetY)
			completion(scrollInfo)
		}
	}

	#if !MAC_APP_STORE
		@objc func webInspectorEnabledDidChange(_ notification: Notification) {
			self.webInspectorEnabled = notification.object! as! Bool
		}
	#endif
}

// MARK: - ScrollInfo

private struct ScrollInfo {

	let contentHeight: CGFloat
	let viewHeight: CGFloat
	let offsetY: CGFloat
	let canScrollDown: Bool
	let canScrollUp: Bool

	init(contentHeight: CGFloat, viewHeight: CGFloat, offsetY: CGFloat) {
		self.contentHeight = contentHeight
		self.viewHeight = viewHeight
		self.offsetY = offsetY

		self.canScrollDown = viewHeight + offsetY < contentHeight
		self.canScrollUp = offsetY > 0.1
	}
}
