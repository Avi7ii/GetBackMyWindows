# 修复说明：自动显示/隐藏 Dock 栏时点击图标无法最小化窗口的问题

## 问题描述

当 macOS 的 Dock 设置为"自动显示和隐藏"时，点击 Dock 图标无法触发最小化窗口的功能。

## 问题原因

原代码使用 `NSScreen.visibleFrame` 来判断鼠标是否在 Dock 区域：

```swift
if NSPointInRect(cocoaPoint, screen.visibleFrame) {
    return false // It's in the content area, definitively NOT the Dock.
}
```

**问题在于**：当 Dock 设置为自动隐藏时，`visibleFrame` 会包含 Dock 所在的区域（因为 Dock 隐藏后空间被释放），导致这个检测方法失效。

## 修复方案

直接检测鼠标是否在屏幕边缘的 100 像素范围内，来判断是否点击了 Dock。

---

## 原代码 vs 修复后代码对比

### 原代码 (`main_original.swift`)

```swift
func isMouseInDockRegion(_ location: CGPoint) -> Bool {
    // Check if the point is within any screen's "safe area" (visibleFrame).
    // If it is inside visibleFrame, it's NOT on the Dock (Dock is excluded from visibleFrame).
    // If it is OUTSIDE visibleFrame but INSIDE frame, it's potentially on the Dock (or Menu Bar).

    for screen in NSScreen.screens {
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else { return true }
        let cocoaY = primaryScreenHeight - location.y
        let cocoaPoint = NSPoint(x: location.x, y: cocoaY)

        if NSPointInRect(cocoaPoint, screen.frame) {
            if NSPointInRect(cocoaPoint, screen.visibleFrame) {
                return false // It's in the content area, definitively NOT the Dock.
            }
            if cocoaY > (screen.frame.maxY - 25) {
                return false // It's the Menu Bar
            }
            return true // It's likely the Dock
        }
    }
    return false
}
```

### 修复后代码 (`main_fixed.swift`)

```swift
func isMouseInDockRegion(_ location: CGPoint) -> Bool {
    // 当 Dock 自动隐藏时，visibleFrame 会包含 Dock 区域
    // 所以我们需要直接检测鼠标是否在屏幕边缘区域（ Dock 可能出现的位置）

    for screen in NSScreen.screens {
        let screenHeight = screen.frame.height
        let screenWidth = screen.frame.width

        // 转换坐标到 Cocoa 坐标系（原点左下）
        let cocoaY = screenHeight - location.y

        // 检查鼠标是否在这个屏幕上
        if location.x >= screen.frame.minX && location.x <= screen.frame.maxX &&
           location.y >= screen.frame.minY && location.y <= screen.frame.maxY {

            // Dock 边缘阈值（像素）
            let dockEdgeThreshold: CGFloat = 100

            // 检查底部边缘区域（底部 Dock）
            if cocoaY <= dockEdgeThreshold {
                if screen.visibleFrame.origin.y <= dockEdgeThreshold {
                    return true
                }
            }

            // 检查左侧边缘区域（左边 Dock）
            if location.x <= dockEdgeThreshold && screen.visibleFrame.origin.x <= dockEdgeThreshold {
                return true
            }

            // 检查右侧边缘区域（右边 Dock）
            if location.x >= screenWidth - dockEdgeThreshold && screen.frame.maxX - screen.visibleFrame.maxX <= dockEdgeThreshold {
                return true
            }
        }
    }

    return false
}
```

---

## 关键差异说明

| 检测位置 | 原代码逻辑 | 修复后代码逻辑 |
|---------|-----------|---------------|
| **底部 Dock** | 依赖 `visibleFrame` 是否排除 Dock 区域 | 检测 `cocoaY <= 100` 且 `visibleFrame.origin.y <= 100` |
| **左侧 Dock** | 依赖 `visibleFrame.origin.x` 判断 | 检测 `x <= 100` 且 `visibleFrame.origin.x <= 100` |
| **右侧 Dock** | 依赖 `visibleFrame.maxX` 判断 | 检测 `x >= screenWidth - 100` 且边缘差值 <= 100 |

## 核心原理

当 Dock 自动隐藏时，鼠标移动到屏幕底部/侧面边缘会触发 Dock 显示。我们通过检测鼠标是否在屏幕边缘的 **100 像素范围**内，来判断是否可能点击了 Dock 图标。

---

## 文件说明

- `main_original.swift` - 原项目完整的 main.swift 文件
- `main_fixed.swift` - 修复后完整的 main.swift 文件
- `README.md` - 本说明文档

---

## 提交信息模板

```
修复自动显示/隐藏 Dock 时点击图标无法最小化的问题

问题描述：
当 macOS 的 Dock 设置为"自动显示和隐藏"时，点击 Dock 图标无法触发最小化窗口的功能。

原因：
原代码使用 NSScreen.visibleFrame 来判断鼠标是否在 Dock 区域，但当 Dock 自动隐藏时，visibleFrame 会包含 Dock 区域，导致检测失效。

解决方案：
直接检测鼠标是否在屏幕边缘的 100 像素范围内，来判断是否点击了 Dock 图标。
```
