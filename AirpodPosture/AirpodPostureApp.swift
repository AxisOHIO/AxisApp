import SwiftUI
import CoreMotion
import UserNotifications
import Combine

@main
struct MenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
     
    var body: some Scene {
        Settings { }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var motionManager = MotionManager()
    var headphoneMotionManager = CMHeadphoneMotionManager()
     
    var badPostureStartTime: Date?
    var badPostureDuration: TimeInterval { motionManager.badPostureDuration }
    var badPostureAlert: NSAlert?
     
    let postureLogger = PostureLogger.shared
     
    private var lastLogTime: Date = .distantPast
    private let logInterval: TimeInterval = 1.0
     
    private var cancellables = Set<AnyCancellable>()
    var badPostureWindow: NSWindow?
    
    // --- NEW CALIBRATION PROPERTIES ---
    
    // Stores the raw CMMotion object
    private var currentAttitude: CMAttitude?
    // Stores the user-defined "good" posture
    private var referenceAttitude: CMAttitude?
    
    // --- END NEW PROPERTIES ---

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        postureLogger.startLogging()
         
        if let button = statusItem?.button {
            if let image = NSImage(named: "axislogowhite") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }
            button.action = #selector(togglePopover)
        }
         
        popover.contentViewController = NSHostingController(rootView: ContentView(motionManager: motionManager))
        popover.behavior = .transient
         
        // --- REFACTORED LOGIC ---
        
        // Start motion updates immediately for UI and calibration
        self.startMotionUpdates()
        
        // Observe toggle changes to turn posture *checking* on/off
        motionManager.$isTracking
            .sink { [weak self] isTracking in
                if isTracking {
                    self?.startPostureChecking()
                } else {
                    self?.stopPostureChecking()
                }
            }
            .store(in: &cancellables)
            
        // --- NEW: Subscribe to calibration signal ---
        motionManager.setCalibrationSubject
            .sink { [weak self] in
                self?.setReferenceAttitude()
                
                // Dismiss the sheet automatically
                self?.motionManager.isCalibrating = false
            }
            .store(in: &cancellables)
        // --- END NEW ---
    }
     
    func showBadPostureAlert(pitch: Double) {
        DispatchQueue.main.async {
            guard self.badPostureWindow == nil else { return }
             
            let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            let window = NSWindow(
                contentRect: screen,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
             
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
             
            let hostingView = NSHostingView(rootView: BadPostureView(pitch: Int(abs(pitch))))
            window.contentView = hostingView
             
            self.badPostureWindow = window
            window.makeKeyAndOrderFront(nil)
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            })
        }
    }

    func dismissBadPostureAlert() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.badPostureWindow?.animator().alphaValue = 0
            }, completionHandler: {
                self.badPostureWindow?.orderOut(nil)
                self.badPostureWindow = nil
            })
        }
    }
     
    // --- NEW: CALIBRATION FUNCTION ---
    func setReferenceAttitude() {
        guard let currentAttitude = self.currentAttitude else {
            print("❌ Cannot calibrate, no motion data")
            return
        }
        self.referenceAttitude = currentAttitude
        
        // When we set a new reference, reset the bad posture timer
        self.badPostureStartTime = nil
        self.dismissBadPostureAlert()
        
        print("✅ New reference attitude set!")
    }

    // --- NEW: STARTS MOTION UPDATES ---
    // This runs as long as the app is open
    func startMotionUpdates() {
        guard headphoneMotionManager.isDeviceMotionAvailable else {
            print("Headphone motion not available")
            // TODO: Show an alert to the user
            return
        }
         
        headphoneMotionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else {
                print("Error: \(error?.localizedDescription ?? "Unknown")")
                return
            }
             
            // 1. Store the latest raw attitude
            self.currentAttitude = motion.attitude
            
            // 2. Publish raw pitch/roll for the UI (like the calibration view)
            self.motionManager.currentPitch = motion.attitude.pitch * 180 / .pi
            self.motionManager.currentRoll = motion.attitude.roll * 180 / .pi

            // 3. If tracking is enabled, check posture
            if self.motionManager.isTracking {
                self.checkPosture(with: motion.attitude)
            }
            
            // 4. Log data (based on raw data, but with the *relative* posture check result)
            // Note: We need to get the isBadPosture bool from checkPosture
            // This is slightly more complex, let's move logging *inside* checkPosture
        }
    }
    
    // --- NEW: POSTURE CHECKING LOGIC ---
    // This is called by startMotionUpdates ONLY if isTracking is true
    func checkPosture(with attitude: CMAttitude) {
            
            // 1. Calculate relative attitude
            let relativeAttitude: CMAttitude
            if let reference = self.referenceAttitude {
                // --- FIX ---
                // We must first copy the attitude, as multiply(byInverseOf:)
                // modifies the object in-place and returns Void.
                relativeAttitude = attitude.copy() as! CMAttitude
                relativeAttitude.multiply(byInverseOf: reference)
                // --- END FIX ---
            } else {
                // If not calibrated, use raw data (original behavior)
                relativeAttitude = attitude
            }
            
            // Get pitch and roll *relative* to the calibrated position
            let pitch = relativeAttitude.pitch * 180 / .pi
            let roll = relativeAttitude.roll * 180 / .pi
             
            let forwardTiltThreshold = -25.0
            let sideTiltThreshold = 20.0
            let isBadPosture = pitch < forwardTiltThreshold || abs(roll) > sideTiltThreshold
             
            // 2. Handle posture alerts
            if isBadPosture {
                if self.badPostureStartTime == nil {
                    self.badPostureStartTime = Date()
                    print("⚠️ Bad posture detected, starting timer...")
                } else {
                    let duration = Date().timeIntervalSince(self.badPostureStartTime!)
                    if duration >= self.badPostureDuration {
                        // Pass the *relative* pitch to the alert
                        self.showBadPostureAlert(pitch: pitch)
                    } else {
                        print("⚠️ Bad posture (\(Int(duration))s) - Relative Pitch: \(Int(pitch))°")
                    }
                }
            } else {
                if self.badPostureStartTime != nil {
                    print("✅ Posture corrected!")
                    self.dismissBadPostureAlert()
                    self.badPostureStartTime = nil
                } else {
                     print("✅ Good posture - Relative Pitch: \(Int(pitch))°, Relative Roll: \(Int(roll))°")
                }
            }
             
            // 3. Handle logging
            let now = Date()
            if now.timeIntervalSince(self.lastLogTime) >= self.logInterval {
                // Log with the *raw* pitch/roll but the *relative* posture status
                let rawPitch = attitude.pitch * 180 / .pi
                let rawRoll = attitude.roll * 180 / .pi
                self.postureLogger.logReading(pitch: rawPitch, roll: rawRoll, isGoodPosture: !isBadPosture)
                self.lastLogTime = now
            }
        }
    // --- RENAMED from startTracking ---
    func startPostureChecking() {
        print("▶️ Posture checking ENABLED")
        // If not calibrated, warn the user
        if self.referenceAttitude == nil {
            print("⚠️ WARNING: Tracking started without calibration. Using absolute angles.")
            // You could pop an alert here
        }
        self.badPostureStartTime = nil // Reset timer
    }
     
    // --- RENAMED from stopTracking ---
    func stopPostureChecking() {
        // Stop timers and dismiss alerts
        badPostureStartTime = nil
        dismissBadPostureAlert()
        print("⏹️ Posture checking DISABLED")
    }
     
    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

//import SwiftUI
//import CoreMotion
//import UserNotifications
//import Combine
//
//@main
//struct MenuBarApp: App {
//    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
//    
//    var body: some Scene {
//        Settings { }
//    }
//}
//
//class AppDelegate: NSObject, NSApplicationDelegate {
//    var statusItem: NSStatusItem?
//    var popover = NSPopover()
//    var motionManager = MotionManager()
//    var headphoneMotionManager = CMHeadphoneMotionManager()
//    
//    var badPostureStartTime: Date?
//    var badPostureDuration: TimeInterval { motionManager.badPostureDuration }
//    var badPostureAlert: NSAlert?
//    
//    let postureLogger = PostureLogger.shared
//    
//    private var lastLogTime: Date = .distantPast
//    private let logInterval: TimeInterval = 1.0
//    
//    func applicationDidFinishLaunching(_ notification: Notification) {
//        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
//        postureLogger.startLogging()
//        
//        if let button = statusItem?.button {
//            button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Menu Bar App")
//            button.action = #selector(togglePopover)
//        }
//        
//        popover.contentViewController = NSHostingController(rootView: ContentView(motionManager: motionManager))
//        popover.behavior = .transient
//        
//        // Observe toggle changes
//        motionManager.$isTracking
//            .sink { [weak self] isTracking in
//                if isTracking {
//                    self?.startTracking()
//                } else {
//                    self?.stopTracking()
//                }
//            }
//            .store(in: &cancellables)
//    }
//    
//    private var cancellables = Set<AnyCancellable>()
//    
//    var badPostureWindow: NSWindow?
//
//    func showBadPostureAlert(pitch: Double) {
//        DispatchQueue.main.async {
//            guard self.badPostureWindow == nil else { return }
//            
//            let window = NSWindow(
//                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
//                styleMask: [.titled, .closable],
//                backing: .buffered,
//                defer: false
//            )
//            
//            window.title = "Posture Alert"
//            window.level = .floating
//            window.center()
//            window.isReleasedWhenClosed = false
//            
//            let hostingView = NSHostingView(rootView: BadPostureView(pitch: Int(abs(pitch))))
//            window.contentView = hostingView
//            
//            self.badPostureWindow = window
//            window.makeKeyAndOrderFront(nil)
//        }
//    }
//
//    func dismissBadPostureAlert() {
//        DispatchQueue.main.async {
//            self.badPostureWindow?.orderOut(nil)
//            self.badPostureWindow = nil
//        }
//    }
//    
//    func startTracking() {
//        guard headphoneMotionManager.isDeviceMotionAvailable else {
//            print("Headphone motion not available")
//            return
//        }
//        
//        headphoneMotionManager.startDeviceMotionUpdates(to: .main) { motion, error in
//            guard let motion = motion, error == nil else {
//                print("Error: \(error?.localizedDescription ?? "Unknown")")
//                return
//            }
//            
//            let pitch = motion.attitude.pitch * 180 / .pi
//            let roll = motion.attitude.roll * 180 / .pi
//            
//            let forwardTiltThreshold = -25.0
//            let sideTiltThreshold = 20.0
//            let isBadPosture = pitch < forwardTiltThreshold || abs(roll) > sideTiltThreshold
//            
//            if isBadPosture {
//                if self.badPostureStartTime == nil {
//                    self.badPostureStartTime = Date()
//                    print("⚠️ Bad posture detected, starting timer...")
//                } else {
//                    let duration = Date().timeIntervalSince(self.badPostureStartTime!)
//                    if duration >= self.badPostureDuration {
//                        self.showBadPostureAlert(pitch: pitch)
//                    } else {
//                        print("⚠️ Bad posture (\(Int(duration))s) - Pitch: \(Int(pitch))°")
//                    }
//                }
//            } else {
//                if self.badPostureStartTime != nil {
//                    print("✅ Posture corrected!")
//                    self.dismissBadPostureAlert()
//                    self.badPostureStartTime = nil
//                } else {
//                    print("✅ Good posture - Pitch: \(Int(pitch))°, Roll: \(Int(roll))°")
//                }
//            }
//            
//            // REPLACE THE OLD logReading LINE WITH THIS:
//            let now = Date()
//            if now.timeIntervalSince(self.lastLogTime) >= self.logInterval {
//                self.postureLogger.logReading(pitch: pitch, roll: roll, isGoodPosture: !isBadPosture)
//                self.lastLogTime = now
//            }
//        }
//    }
//    
//    func stopTracking() {
//        headphoneMotionManager.stopDeviceMotionUpdates()
//        badPostureStartTime = nil
//        print("Stopped tracking")
//    }
//    
//    @objc func togglePopover() {
//        if let button = statusItem?.button {
//            if popover.isShown {
//                popover.performClose(nil)
//            } else {
//                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
//            }
//        }
//    }
//    
//}
