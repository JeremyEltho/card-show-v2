import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

struct ImagePreprocessor {
    static func perspectiveCorrect(_ image: CIImage, rect: VNRectangleObservation) -> CIImage {
        let imageSize = image.extent.size
        func toVec(_ p: CGPoint) -> CIVector {
            CIVector(x: p.x * imageSize.width, y: p.y * imageSize.height)
        }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(toVec(rect.topLeft), forKey: "inputTopLeft")
        filter.setValue(toVec(rect.topRight), forKey: "inputTopRight")
        filter.setValue(toVec(rect.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(toVec(rect.bottomRight), forKey: "inputBottomRight")
        return filter.outputImage ?? image
    }

    static func cropTitleBand(_ image: CIImage) -> CIImage {
        let ext = image.extent
        let crop = CGRect(x: ext.minX, y: ext.maxY * 0.75,
                          width: ext.width, height: ext.height * 0.25)
        return image.cropped(to: crop)
    }

    static func enhanceContrast(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        filter.setValue(1.5, forKey: kCIInputContrastKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        return filter.outputImage ?? image
    }
}
