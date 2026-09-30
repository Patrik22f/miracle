import SwiftUI

struct MiracleMark: View {
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: MiracleArtwork.menuImage())
            .resizable().renderingMode(.template)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
