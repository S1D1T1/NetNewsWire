//
//  YouTubeVideoInfo.swift
//  NetNewsWire
//
// added by S1D1T1 to display youtube video DX.


///https://claude.ai/share/1223596b-01bc-432f-a0d6-d5ac5b24cf70

import Foundation

class YouTubeVideoInfo {
	static let apiKey = "<YOUR API KEY HERE>"

	static func isYouTubeVideo(_ url: URL?) -> Bool {
		guard let url else { return false }
		return url.host?.contains("youtube.com") == true ||
		url.host?.contains("youtu.be") == true
	}

	static func extractVideoID(from url: URL) -> String? {
		// Handle youtube.com/watch?v=VIDEO_ID format
		if url.host?.contains("youtube.com") == true,
		   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		   let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
			return videoID
		}

		// Handle youtu.be/VIDEO_ID format
		if url.host?.contains("youtu.be") == true {
			return url.pathComponents.last
		}
		return nil
	}

	static func fetchVideoDescription(_ videoID: String) async -> String? {
		let urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=\(videoID)&key=\(apiKey)"
		guard let url = URL(string: urlString) else { return nil }

		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

			if let items = json?["items"] as? [[String: Any]],
			   let firstItem = items.first,
			   let snippet = firstItem["snippet"] as? [String: Any],
			   let description = snippet["description"] as? String {
				return description
			}
		} catch {
			print("YouTube API error: \(error)")
		}

		return nil
	}

	static func formatDescriptionAsHTML(_ description: String) -> String {
		// Convert line breaks to <br> tags
		let htmlDescription = description
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\n", with: "<br>") // do this last

		return """
		<div style='background: #f9f9f9; padding: 20px; margin: 20px 0; border-radius: 8px; border-left: 4px solid #ff0000;'>
			<h3 style='margin-top: 0; color: #333;'>Video Description</h3>
			<div style='color: #555; line-height: 1.6;'>\(htmlDescription)</div>
		</div>
		"""
	}
}

extension DetailWebViewController {
	func addYouTubeInfo(_ articleURL: URL, _ rendering: ArticleRenderer.Rendering) -> ArticleRenderer.Rendering {
		guard let videoID = YouTubeVideoInfo.extractVideoID(from: articleURL) else {
			return rendering
		}

		// Generate a unique div ID for this video
		let divID = "youtube-info-\(videoID)"

		// Inject placeholder HTML with the div ID
		let placeholderHTML = """
		<div id="\(divID)" style='background: #f9f9f9; padding: 20px; margin: 20px 0; border-radius: 8px;'>
			<p>Loading YouTube video info...</p>
		</div>
		"""

		// Start async fetch
		Task {
			if let description = await YouTubeVideoInfo.fetchVideoDescription(videoID) {
				let formattedHTML = YouTubeVideoInfo.formatDescriptionAsHTML(description)

				// Update the WebView content
				await MainActor.run {
					let js = """
					document.getElementById('\(divID)').innerHTML = `\(formattedHTML)`;
					"""
					self.webView.evaluateJavaScript(js)
				}
			}
		}

		return ArticleRenderer.Rendering(
						style: rendering.style,
						html: rendering.html + placeholderHTML,
						title: rendering.title,
						baseURL: rendering.baseURL)
	}
}
