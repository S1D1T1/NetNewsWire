# NetNewsWire with YouTube Enhancement

This is a fork of [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) that adds automatic YouTube video description fetching for YouTube RSS feeds.

## What This Does

When you subscribe to YouTube channels via RSS in NetNewsWire, the feed only includes video titles - no descriptions or transcripts. This enhancement automatically fetches and displays the full video description when you select a YouTube video in your feed.

## Why This Fork Exists

YouTube's RSS feeds are sparse, containing only:
- Video title
- Link to YouTube
- Thumbnail
- Basic metadata

The actual video description (which often contains timestamps, links, and important context) is not included in the RSS feed. This fork adds that missing information by making YouTube API calls when you view a video.

## Technical Approach

This enhancement works at the display layer rather than modifying NetNewsWire's core RSS parsing:

1. When an article is displayed, it checks if the URL is a YouTube video
2. If so, it extracts the video ID and fetches the description via YouTube Data API v3
3. The description is then injected into the article view using JavaScript

This approach was chosen to:
- Minimize changes to NetNewsWire's architecture
- Only fetch data for videos you actually view (API efficiency)
- Keep the enhancement completely separate from core RSS functionality

**The entire implementation consists of:**
- **5 lines added** to `DetailWebViewController.swift` to check for YouTube videos and call the enhancement
- **One new file**,`YouTubeVideoInfo.swift` containing all YouTube-specific logic

This minimal footprint makes the enhancement easy to review, maintain, or remove if needed.

## Setup

1. Clone this fork and build in Xcode (see original NetNewsWire build instructions)
2. Get a YouTube Data API v3 key from [Google Cloud Console](https://console.cloud.google.com/)
3. Add your API key to `YouTubeVideoInfo.swift`:
   ```swift
   static let apiKey = "YOUR_API_KEY_HERE"
**You MUST insert an API Key, or no video descriptions will appear**
