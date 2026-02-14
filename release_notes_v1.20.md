# Release v1.20 - WeChat Perfection & Performance Boost

This release focuses on optimizing the experience for WeChat users and significantly improving overall system performance.

## 🚀 New Features & Improvements

### 🟢 WeChat Auxiliary Window Support (Perfected)
- **Full Support for Mini Programs & Articles**: Clicking the green "WeChatAppEx" Dock icon now correctly minimizes and restores these windows.
- **Smart Restore**: Fixed an issue where clicking the icon would fail to restore a minimized window. The app now intelligently detects if the window is minimized, hidden, or active, and performs the correct action (Restore/Activate/Minimize).
- **Async Processing**: All logic is now handled asynchronously in the background, ensuring immediate click response without any UI blocking.

### ⚡ Performance Optimization (Geofencing)
- **Zero-Lag Animations**: Implemented a geometric "Geofence" check. The app now only performs accessibility queries when the mouse is actually in the Dock area.
- **95% Load Reduction**: Clicks in the rest of the screen (e.g., browsing, typing) no longer trigger any heavy processing, eliminating stutter during window resizing or high-load scenarios.

### 🖱️ Smart Main Icon Logic
- **Context-Aware Click**: Clicking the main WeChat icon now intelligently decides:
    - If you are viewing an **Article/Mini Program**: It activates the **Main Chat Window** (Back to Chat).
    - If you are already on the **Main Chat**: It **Minimizes** the app.
- This resolves the conflict where users couldn't easily switch back to chat from an article.

## 🛠️ Fixes
- Fixed potential "Event Tap Timeout" issues by moving all AX calls to background threads.
- Added robustness checks to ensure windows are explicitly un-minimized before activation.

---
**Build Artifact**: `GetBackMyWindows.app.zip`
**SHA256**: (Auto-generated on upload)
