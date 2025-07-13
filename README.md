# NetNewsWire with YouTube Enhancement

This is a fork of [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) that automatically fetches YouTube video description, duration, & thumbnail for YouTube RSS feeds.  
**NOTE: GOOGLE API KEY IS REQUIRED** Currently, the key must be inserted in the source, so you must be able to build this project in xcode in order to try out the feature. Future improvement: read the API KEY from a config file, or allow user to supply via UI. Once I have that, I can post a runnable binary.

## What This Does

YouTube channels' RSS feed only includes video titles - no descriptions or transcripts. This enhancement automatically fetches and displays the full video description when you select a YouTube video in your feed.  
It also indicates when entries are youtube "shorts", by prepending 📱 to the item's title.

### Without Video descriptions & thumbnails:
![Screenshot 2025-07-13 at 3 06 20 PM](https://github.com/user-attachments/assets/91aa628f-f8b5-4c97-8768-46138a1fc7bf)


### With Video descriptions & thumbnails:
![Screenshot 2025-07-13 at 3 05 11 PM](https://github.com/user-attachments/assets/7f7f0c54-9c80-47fc-9685-e5e8a8c0f65b)


## Why This Fork Exists

YouTube's RSS feeds are sparse, containing only:
- Video title
- Link to YouTube
- Thumbnail
- Basic metadata

The actual video description (which often contains timestamps, links, and important context) is not included in the RSS feed. This fork adds that missing information by making YouTube API calls when you view a video. In short, it's the stuff I use to determine if I actually want to watch.

## Technical Approach

This enhancement only uses Google's official YouTube APIs.

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

## Future 
potential feature enhancement: batch retrieve/ import all YT subscriptions as feeds.  
show some/all of transcript. (no official YouTube API, but solutions exist, such as python library, "youtube-transcript-api"

## Setup

1. Clone this fork and build in Xcode (see original NetNewsWire build instructions)
2. Get a YouTube Data API v3 key from [Google Cloud Console](https://console.cloud.google.com/)
3. Add your API key to `YouTubeVideoInfo.swift`:
   ```swift
   static let apiKey = "YOUR_API_KEY_HERE"
**You MUST insert an API Key, and rebuild the app, or no video descriptions will appear**
