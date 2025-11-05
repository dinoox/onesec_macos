import SwiftUI

enum AnimationConstants {
    static let springResponse: CGFloat = 0.5
    static let springDamping: CGFloat = 0.825
    static let morphSpringResponse: CGFloat = 1.5

    static var defaultSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    static var quickSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.7)
    }

    static var morphSpring: Animation {
        .spring(response: morphSpringResponse, dampingFraction: springDamping)
    }
}

extension Animation {
    static var cardAnimation: Animation { AnimationConstants.defaultSpring }
    static var springAnimation: Animation { AnimationConstants.defaultSpring }
    static var quickSpringAnimation: Animation { AnimationConstants.quickSpring }
    static var morphAnimation: Animation { AnimationConstants.morphSpring }
}
