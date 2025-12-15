import SwiftUI

// 1. Definicja efektu rozmycia (musi być tylko raz w projekcie!)
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Używamy .popover lub .sidebar dla jaśniejszego, mroźnego efektu
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.blendingMode = .withinWindow
    }
}

// 2. Widok blokady
struct LockScreenView: View {
    @State private var pinInput = ""
    @State private var shakeAmount: CGFloat = 0
    @State private var glowOpacity = 0.5
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // WARSTWA 1: TŁO ROZMYTE
            VisualEffectBlur()
                .ignoresSafeArea()
            
            // WARSTWA 2: ATMOSFERA (Kolorowe plamy)
            // To one sprawią, że ekran przestane być płaski i szary!
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: -100, y: -100)
                
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: 250, height: 250)
                    .blur(radius: 60)
                    .offset(x: 100, y: 100)
            }
            
            // WARSTWA 3: Delikatne przyciemnienie dla kontrastu tekstu
            Color.black.opacity(0.2).ignoresSafeArea()
            
            // WARSTWA 4: ZAWARTOŚĆ
            VStack(spacing: 30) {
                
                // Ikona kłódki z animowaną poświatą
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: 90, height: 90)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(glowOpacity), radius: 15)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        glowOpacity = 1.0
                    }
                }
                
                VStack(spacing: 5) {
                    Text("Whispers")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text("Aplikacja jest zablokowana")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                // Pole PIN
                HStack {
                    SecureField("", text: $pinInput)
                        .placeholder(when: pinInput.isEmpty) {
                            Text("Podaj PIN").foregroundStyle(.white.opacity(0.3))
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .frame(width: 140)
                        .focused($isFocused)
                        .onSubmit { validatePIN() }
                }
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                
                // Przycisk Odblokuj
                Button(action: validatePIN) {
                    Text("Odblokuj")
                        .fontWeight(.medium)
                        .padding(.horizontal, 25)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2), lineWidth: 1)
                )
            }
            .offset(x: shakeAmount)
        }
        .onAppear { isFocused = true }
    }
    
    func validatePIN() {
        if AppLockManager.shared.unlock(with: pinInput) {
            // Sukces - odblokowano
            pinInput = ""
        } else {
            // Błąd
            pinInput = ""
            
            // 1. Haptic Feedback (Wibracja)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            
            // 2. Sekwencja Animacji Shake (Wymuszona przez DispatchQueue)
            
            // Krok A: W prawo
            withAnimation(.linear(duration: 0.05)) {
                shakeAmount = 10
            }
            
            // Krok B: W lewo (szybka kontra)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.linear(duration: 0.05)) {
                    shakeAmount = -10
                }
            }
            
            // Krok C: Powrót na środek (sprężyście)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.3, blendDuration: 0)) {
                    shakeAmount = 0
                }
            }
        }
    }
}

// Extension dla Placeholdera (żeby tekst "Podaj PIN" był ładny)
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
