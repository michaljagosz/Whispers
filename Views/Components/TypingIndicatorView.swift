import SwiftUI

struct TypingIndicatorView: View { @State private var dots = 3; @State private var anim = false; var body: some View { HStack(spacing: 4) { ForEach(0..<dots, id: \.self) { i in Circle().frame(width: 6, height: 6).foregroundStyle(.secondary).opacity(anim ? 0.3 : 1).scaleEffect(anim ? 0.8 : 1).animation(.easeInOut(duration: 0.6).repeatForever().delay(0.2 * Double(i)), value: anim) } }.onAppear { anim = true } } }
