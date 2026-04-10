import Foundation
import SwiftUI

enum AppConstants {
    // Window
    static let defaultWindowWidth: CGFloat = 960
    static let defaultWindowHeight: CGFloat = 660
    static let minimumWindowWidth: CGFloat = 800
    static let minimumWindowHeight: CGFloat = 540
    static let sidebarWidth: CGFloat = 200

    // Layout
    static let panelPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 12
    static let actionButtonTopPadding: CGFloat = 16
    static let headingBottomPadding: CGFloat = 16

    // Drop Zone
    static let singleFileDropHeight: CGFloat = 80
    static let multiFileDropHeight: CGFloat = 120
    static let dropZoneDashPattern: [CGFloat] = [8, 4]

    // Thumbnails
    static let thumbnailSize: CGSize = CGSize(width: 44, height: 62)
    static let gridThumbnailSize: CGSize = CGSize(width: 120, height: 160)

    // Animation
    static let dropZoneHoverDuration: Double = 0.15
    static let bannerSlideDuration: Double = 0.25
    static let bannerDismissDuration: Double = 0.20
    static let passwordExpandDuration: Double = 0.20
    static let thumbnailSelectionDuration: Double = 0.10
    static let thumbnailFadeInDuration: Double = 0.20

    // Timing
    static let cancelButtonDelay: TimeInterval = 2.0
    static let bannerAutoDismiss: TimeInterval = 10.0
    static let rejectionMessageDismiss: TimeInterval = 5.0
    static let orphanTempFileAge: TimeInterval = 3600 // 1 hour

    // Recent Files
    static let maxRecentFilesPerTool = 5

    // Temp files
    static let tempFilePrefix = ".pdftool_"
    static let tempFileSuffix = ".tmp"
}

enum PreferenceKeys {
    static let defaultSaveLocation = "defaultSaveLocation"
    static let openAfterOperation = "openAfterOperation"
    static let ocrLanguage = "ocrLanguage"
    static let ocrAccuracy = "ocrAccuracy"
    static let lastWindowFrame = "lastWindowFrame"
}
