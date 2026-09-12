import Foundation
import Photos
import UIKit

/// People screenshot confirmations, renewal emails and bookings all day. With permission, LEVER notices new
/// screenshots and offers to read them — nothing is scanned until the user taps.
struct ScreenshotWatcher: Sendable {
    enum Access { case granted, limited, denied, notDetermined }

    var access: Access {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: .granted
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Access {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized: return .granted
        case .limited: return .limited
        default: return .denied
        }
    }

    /// Screenshots created after `since`, newest first (capped so a backlog never floods the UI).
    func newScreenshots(since: Date?, limit: Int = 12) -> [PHAsset] {
        guard access == .granted || access == .limited else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        if let since {
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0 AND creationDate > %@", PHAssetMediaSubtype.photoScreenshot.rawValue, since as NSDate)
        } else {
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        }
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func image(for asset: PHAsset, maxDimension: CGFloat = 2400) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: maxDimension, height: maxDimension), contentMode: .aspectFit, options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
