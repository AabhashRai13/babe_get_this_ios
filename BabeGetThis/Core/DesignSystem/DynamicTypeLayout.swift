import SwiftUI

extension DynamicTypeSize {
    /// List and item names: one line, like Android, at the standard sizes. At the accessibility
    /// sizes one line shows only a few letters ("Sunda…"), so names wrap instead.
    var nameLineLimit: Int { isAccessibilitySize ? 3 : 1 }
}
