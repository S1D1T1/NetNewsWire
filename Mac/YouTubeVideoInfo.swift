//
//  YouTubeVideoInfo.swift
//  NetNewsWire
//
// added by S1D1T1 to display youtube video DX.


///https://claude.ai/share/1223596b-01bc-432f-a0d6-d5ac5b24cf70

import Foundation

class YouTubeVideoInfo {
	static let apiKey = "<YOUR API KEY HERE>"

	/// filter Youtube videos
	static func isYouTubeVideo(_ url: URL?) -> Bool {
		guard let url else { return false }
		return url.host?.contains("youtube.com") == true ||
		url.host?.contains("youtu.be") == true
	}

	/// filter for YouTube Shorts - used to indicate short videos at a higher level of the UI - the article timeline.
	static func isYouTubeShort(_ article:Article) -> Bool {
		if let url = article.url,
			isYouTubeVideo(url),
		   url.absoluteString.contains("/shorts/") {
			return true
		}
		return false
	}

	/// the key to identifying any youtube video. it's listed in the feed data
	static func extractVideoID(from article: Article) -> String? {
		// Check if it's in the unique ID (RSS guid)
		let uniqueID = article.uniqueID
		  if uniqueID.hasPrefix("yt:video:") {
			return String(uniqueID.dropFirst(9))
		}

		// Fall back to URL parsing
		return extractVideoID(from: article)
	}

	/// using Youtube official API, get the accompaying text beneath a video. This is not in the feed data.
	/// requires an API key.
	static func fetchVideoDescription(_ videoID: String) async -> String? {
		guard apiKey != "<YOUR API KEY HERE>" else {
			print("**API KEY MUST BE SUPPLIED BEFORE YOU CAN RETRIEVE YOUTUBE VIDEO DESCRIPTIONS**")
			return String("**API KEY MUST BE SUPPLIED BEFORE YOU CAN RETRIEVE YOUTUBE VIDEO DESCRIPTIONS**")
		}
		let urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=\(videoID)&key=\(apiKey)"
		guard let url = URL(string: urlString) else { return nil }

		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

			if let items = json?["items"] as? [[String: Any]],
			   let firstItem = items.first,
			   let snippet = firstItem["snippet"] as? [String: Any],
			   let description = snippet["description"] as? String
			{
				return description
			}
		} catch {
			print("YouTube API error: \(error)")
		}

		return nil
	}

	/// formatting for video dx
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

	// the feed actually includes the thumbnail link with each entry. but hard to dig out from here.
	/// just as easy to use a known formula.
	static func thumbnailURL(for videoID: String) -> String {
		// YouTube thumbnails follow a predictable pattern
		return "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
		// Or use maxresdefault.jpg for higher quality
	}

}

/// extend DetailWebViewController to display extra info for Youtube Videos. Including video description and thumbnail
extension DetailWebViewController {
	func addYouTubeInfo(_ articleURL: URL, _ rendering: ArticleRenderer.Rendering) -> ArticleRenderer.Rendering {
		guard let article,
			  let videoID = YouTubeVideoInfo.extractVideoID(from: article) else {
			return rendering
		}

		// Use thumbnail from RSS feed
		let imageURL = YouTubeVideoInfo.thumbnailURL(for: videoID)
		let	thumbnailHTML = """
	<div style='margin: 20px 0;'>
	 <img src='\(imageURL)' style='max-width: 100%; height: auto; border-radius: 8px;' />
	</div>
	"""
		// Generate a unique div ID for this video
		let divID = "youtube-info-\(videoID)"

		// Inject placeholder HTML with the div ID
		// adding: thumb
		let placeholderHTML = """
	  <div id="\(divID)" style='background: #f9f9f9; padding: 20px; margin: 20px 0; border-radius: 8px;'>
	   \(thumbnailHTML)
	   <p>Loading YouTube video description...</p>
	  </div>
	  """

		// Start async fetch
		// when it returns, inject the data into the placeholder html.
		Task {
			if let description = await YouTubeVideoInfo.fetchVideoDescription(videoID) {
				let formattedHTML = YouTubeVideoInfo.formatDescriptionAsHTML(description)

				// Update the WebView content
				await MainActor.run {
					let js = """
					const div = document.getElementById('\(divID)');
					const img = div.querySelector('img');
					div.innerHTML = `\(formattedHTML)`;
					if (img) { div.insertBefore(img, div.firstChild); }
					"""
					self.webView.evaluateJavaScript(js)
				}
			}
		}

		return ArticleRenderer.Rendering(
			style: rendering.style,
			html: rendering.html + placeholderHTML,
			title: rendering.title,
			baseURL: rendering.baseURL
		)
	}
}
