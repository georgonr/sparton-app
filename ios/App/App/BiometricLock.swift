import UIKit
import LocalAuthentication

/// Odomknutie appky cez Face ID / Touch ID alebo kód zariadenia (rovnako ako Android). Zapína sa po prihlásení
/// (otázka raz) alebo v Nastaveniach appky (podržanie ikony → Nastavenia appky). Pri štarte a po návrate z pozadia
/// dlhšom ako 5 minút prekryje obsah, kým sa používateľ neoverí. Biometrické údaje ostávajú v zariadení.
final class BiometricLock {
    static let lockAfter: TimeInterval = 5 * 60
    private weak var host: UIViewController?
    private var overlay: UIView?
    private var backgroundAt: Date?
    private var prompting = false

    init(host: UIViewController) { self.host = host }

    var isEnabled: Bool { Prefs.d.bool(forKey: Prefs.bioEnabled) }
    var isLocked: Bool { overlay?.isHidden == false }

    /// Face ID / Touch ID nastavené (ponuka po prihlásení) – bez nich ponuku nezobrazíme.
    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var canAuthenticate: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// Názov podľa zariadenia: Face ID / Touch ID / kód.
    var methodName: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return L("bio.passcode")
        }
    }

    func onColdStart() { if isEnabled { lock() } }
    func onBackground() { backgroundAt = Date() }

    func onForeground() {
        defer { backgroundAt = nil }
        guard isEnabled, !isLocked, let at = backgroundAt else { return }
        if Date().timeIntervalSince(at) > BiometricLock.lockAfter { lock() }
    }

    func lock() {
        guard let host = host else { return }
        guard canAuthenticate else {
            // používateľ zrušil kód zariadenia – zámok appky by ju zamkol navždy, preto sa vypne
            Prefs.d.set(false, forKey: Prefs.bioEnabled)
            overlay?.isHidden = true
            return
        }
        if overlay == nil {
            let v = UIView()
            v.backgroundColor = UIColor(named: "SpartonDark") ?? UIColor(red: 0.043, green: 0.165, blue: 0.098, alpha: 1)
            v.translatesAutoresizingMaskIntoConstraints = false
            v.accessibilityIdentifier = "lock-overlay"
            let logo = UIImageView(image: UIImage(named: "Splash"))
            logo.contentMode = .scaleAspectFill // úvodný obrázok spartON (logo v strede) ako pozadie
            logo.translatesAutoresizingMaskIntoConstraints = false
            let title = UILabel()
            title.text = L("lock.title")
            title.textColor = .white
            title.font = .systemFont(ofSize: 22, weight: .bold)
            title.textAlignment = .center
            title.translatesAutoresizingMaskIntoConstraints = false
            var cfg = UIButton.Configuration.filled()
            cfg.baseBackgroundColor = UIColor(red: 0.784, green: 0.961, blue: 0.376, alpha: 1)
            cfg.baseForegroundColor = UIColor(red: 0.043, green: 0.165, blue: 0.098, alpha: 1)
            cfg.cornerStyle = .large
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28)
            let b = UIButton(configuration: cfg)
            b.setTitle(L("lock.unlock"), for: .normal)
            b.accessibilityIdentifier = "lock-unlock"
            b.translatesAutoresizingMaskIntoConstraints = false
            b.addAction(UIAction { [weak self] _ in self?.prompt(nil) }, for: .touchUpInside)
            v.addSubview(logo); v.addSubview(title); v.addSubview(b)
            host.view.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: host.view.leadingAnchor), v.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                v.topAnchor.constraint(equalTo: host.view.topAnchor), v.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
                logo.leadingAnchor.constraint(equalTo: v.leadingAnchor), logo.trailingAnchor.constraint(equalTo: v.trailingAnchor),
                logo.topAnchor.constraint(equalTo: v.topAnchor), logo.bottomAnchor.constraint(equalTo: v.bottomAnchor),
                title.topAnchor.constraint(equalTo: v.centerYAnchor, constant: 110),
                title.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24), title.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -24),
                b.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 28), b.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            ])
            overlay = v
        }
        overlay?.isHidden = false
        if let o = overlay { host.view.bringSubviewToFront(o) }
        DispatchQueue.main.async { self.prompt(nil) }
    }

    /// Overenie; bez callbacku odomkne appku, s callbackom potvrdí zmenu nastavenia.
    func prompt(_ onSuccess: (() -> Void)?) {
        guard !prompting else { return }
        prompting = true
        let c = LAContext()
        c.localizedCancelTitle = L("bio.cancel")
        c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("bio.reason")) { ok, _ in
            DispatchQueue.main.async {
                self.prompting = false
                guard ok else { return } // zámok ostáva; tlačidlo „Odomknúť“ skúsi znova
                if let s = onSuccess { s() } else { self.overlay?.isHidden = true }
            }
        }
    }

    func setEnabled(_ on: Bool) {
        Prefs.d.set(on, forKey: Prefs.bioEnabled)
        Prefs.d.set(true, forKey: Prefs.bioAsked)
    }
}
