import SwiftUI
import Combine // Import Combine for PassthroughSubject
import CoreMotion // Import CoreMotion for CMAttitude

class MotionManager: ObservableObject {
    @Published var isTracking = false
    @Published var badPostureDuration: TimeInterval = 5.0
    
    // --- New properties for Calibration ---
    @Published var isCalibrating = false
    
    // Live (raw) motion data for the UI
    @Published var currentPitch: Double = 0.0
    @Published var currentRoll: Double = 0.0
    
    // Calibration extremes
    var calibrationMinPitch: Double = 0
    var calibrationMaxPitch: Double = 0
    var calibrationMinRoll: Double = 0
    var calibrationMaxRoll: Double = 0
    
    // Signal to tell the AppDelegate to capture the current attitude
    let setCalibrationSubject = PassthroughSubject<Void, Never>()
}

struct ContentView: View {
    @ObservedObject var motionManager: MotionManager
    @State private var isHoveringTime = false
     
    var body: some View {
        VStack(spacing: 4) {
            // Top Bar with Calibration and Time Delay
            HStack {
                // Calibration Button
                Button(action: {
                    // --- MODIFIED ACTION ---
                    // Open the calibration sheet
                    motionManager.isCalibrating = true
                    // --- END MODIFICATION ---
                }) {
                    Image(systemName: "scope")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.thinMaterial)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Time Delay Button
                Button(action: {
                    // Cycle through: 5 -> 10 -> 15 -> 20 -> 25 -> 30 -> 5
                    let currentValue = Int(motionManager.badPostureDuration)
                    if currentValue >= 30 {
                        motionManager.badPostureDuration = 5.0
                    } else {
                        motionManager.badPostureDuration = TimeInterval(currentValue + 5)
                    }
                }) {
                    Group {
                        if isHoveringTime {
                            Text("\(Int(motionManager.badPostureDuration))")
                                .font(.system(size: 16, weight: .semibold))
                        } else {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 18, weight: .medium))
                        }
                    }
                    .foregroundColor(.orange)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.thinMaterial)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isHoveringTime = hovering
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
             
            // AirPods Image - Clickable
            Button(action: {
                motionManager.isTracking.toggle()
            }) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 120))
                    .foregroundColor(motionManager.isTracking ? .blue : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 20)
             
            // Axis Title
            Text("AXIS")
                .font(.system(size: 16, weight: .light))
                .tracking(6)
                .foregroundColor(.secondary)
                .opacity(0.8)
                .frame(maxWidth: .infinity)
            
            Spacer()
                .frame(maxHeight: 20)
        }
        .frame(width: 280, height: 290)
        .background(.ultraThinMaterial)
        // --- ADDED MODIFIER ---
        // This presents the new CalibrationView as a sheet
        .sheet(isPresented: $motionManager.isCalibrating) {
            CalibrationView(motionManager: motionManager)
        }
        // --- END ADDITION ---
    }
}

// --- NEW CALIBRATION VIEW ---
struct CalibrationView: View {
    @ObservedObject var motionManager: MotionManager
    @Environment(\.dismiss) var dismiss

    @State private var calibrationProgress: Double = 0.0
    private let totalMovementRequired: Double = 150.0
    
    @State private var lastPitch: Double = 0.0
    @State private var lastRoll: Double = 0.0
    
    // Track extremes for threshold calculation
    @State private var minPitch: Double = .infinity
    @State private var maxPitch: Double = -.infinity
    @State private var minRoll: Double = .infinity
    @State private var maxRoll: Double = -.infinity
    
    // Orbit particles
    @State private var orbitParticles: [OrbitParticle] = []
    @State private var rotationAngle: Double = 0
    @State private var opacity: Double = 0
    
    var isComplete: Bool { calibrationProgress >= totalMovementRequired }
    var progressPercentage: Double { (calibrationProgress / totalMovementRequired) * 100 }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 20)
            
            // Header
            Text("Calibration")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary)
            
            // Instruction area with fixed height to prevent layout shift
            ZStack {
                Color.clear
                if !isComplete {
                    Text("Move your head in a circular motion")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                        .opacity(0.8)
                        .transition(.opacity)
                }
            }
            .frame(height: 22) // reserve constant vertical space
            
            // Main animation area
            ZStack {
                // Progress ring (only shows as progress is made)
                Circle()
                    .trim(from: 0, to: progressPercentage / 100)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progressPercentage)
                
                // Center content with fixed space to prevent layout shift
                ZStack {
                    // Reserve consistent space in the center
                    Color.clear
                        .frame(width: 160, height: 100)
                        .allowsHitTesting(false)

                    // Percentage state
                    Text("\(Int(progressPercentage))%")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.blue)
                        .opacity(isComplete ? 0 : 0.6)
                        .animation(.easeInOut(duration: 0.2), value: isComplete)

                    // Complete state
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)

                            Text("Complete")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.green)
                        }

                        Text("Sit in your ideal posture")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .opacity(0.8)
                    }
                    .opacity(isComplete ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isComplete)
                }

                // Orbit rings
                ForEach(0..<3) { ring in
                    Circle()
                        .stroke(Color.blue.opacity(0.1 - Double(ring) * 0.03), lineWidth: 1)
                        .frame(width: 100 + CGFloat(ring * 40), height: 100 + CGFloat(ring * 40))
                }
                
                // Animated orbit particles
                ForEach(orbitParticles) { particle in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue, .blue.opacity(0.4)],
                                center: .center,
                                startRadius: 0,
                                endRadius: particle.size / 2
                            )
                        )
                        .frame(width: particle.size, height: particle.size)
                        .offset(x: particle.orbitRadius * cos(particle.angle + rotationAngle),
                               y: particle.orbitRadius * sin(particle.angle + rotationAngle))
                        .opacity(particle.opacity)
                        .blur(radius: 0.5)
                }
            }
            .frame(width: 220, height: 220, alignment: .center)
    
            Spacer()
                .frame(height: 20)
            
            // Action button
            Button(action: {
                if isComplete {
                    // Store extremes in MotionManager
                    motionManager.calibrationMinPitch = minPitch
                    motionManager.calibrationMaxPitch = maxPitch
                    motionManager.calibrationMinRoll = minRoll
                    motionManager.calibrationMaxRoll = maxRoll
                    
                    withAnimation(.easeOut(duration: 0.2)) {
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        motionManager.setCalibrationSubject.send()
                    }
                }
            }) {
                Text(isComplete ? "Set Neutral Posture" : "Calibrating...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isComplete ? Color.blue : Color.gray.opacity(0.5))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isComplete)
            .padding(.horizontal, 40)
            
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    dismiss()
                }
            }) {
                Text("Cancel")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
                .frame(height: 20)
        }
        .frame(width: 320, height: 500)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
        .opacity(opacity)
        .onAppear {
            lastPitch = motionManager.currentPitch
            lastRoll = motionManager.currentRoll
            startOrbitAnimation()
            withAnimation(.easeIn(duration: 0.2)) {
                opacity = 1
            }
        }
        .onChange(of: motionManager.currentPitch) { _, _ in
            checkMovement()
        }
        .onChange(of: motionManager.currentRoll) { _, _ in
            checkMovement()
        }
    }
    
    func startOrbitAnimation() {
        // Continuous rotation
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            rotationAngle += 0.02
        }
    }
    
    func checkMovement() {
        let deltaPitch = abs(motionManager.currentPitch - lastPitch)
        let deltaRoll = abs(motionManager.currentRoll - lastRoll)
        let movementDelta = deltaPitch + deltaRoll
        
        if !isComplete && movementDelta > 0.5 {
            calibrationProgress = min(calibrationProgress + movementDelta, totalMovementRequired)
            
            // Track extremes for threshold calculation
            minPitch = min(minPitch, motionManager.currentPitch)
            maxPitch = max(maxPitch, motionManager.currentPitch)
            minRoll = min(minRoll, motionManager.currentRoll)
            maxRoll = max(maxRoll, motionManager.currentRoll)
            
            // Add new orbit particle
            let radius = Double.random(in: 50...110)
            let angle = Double.random(in: 0...(2 * .pi))
            let size = Double.random(in: 6...12)
            
            let particle = OrbitParticle(
                angle: angle,
                orbitRadius: radius,
                size: size,
                opacity: 1.0
            )
            
            orbitParticles.append(particle)
            
            // Fade and remove old particles
            if orbitParticles.count > 20 {
                orbitParticles.removeFirst()
            }
            
            // Gradually fade particles
            for i in 0..<orbitParticles.count {
                orbitParticles[i].opacity = 0.3 + (Double(i) / Double(orbitParticles.count)) * 0.7
            }
        }
        
        lastPitch = motionManager.currentPitch
        lastRoll = motionManager.currentRoll
    }
}

struct OrbitParticle: Identifiable {
    let id = UUID()
    var angle: Double
    var orbitRadius: Double
    var size: Double
    var opacity: Double
}

struct TrailPoint: Identifiable {
    let id = UUID()
    var position: CGPoint
    var opacity: Double
}


struct BadPostureView: View {
    let pitch: Int
    @State private var opacity: Double = 0
     
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
           
            Text("Bad Posture!")
                .font(.title2)
                .fontWeight(.bold)
           
            Text("Head tilted \(pitch)° forward")
                .foregroundColor(.secondary)
           
            Text("Sit up straight")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                opacity = 1
            }
        }
    }
}

//import SwiftUI
//
//class MotionManager: ObservableObject {
//    @Published var isTracking = false
//    @Published var badPostureDuration: TimeInterval = 5.0
//}
//
//struct ContentView: View {
//    @ObservedObject var motionManager: MotionManager
//    @State private var isHoveringTime = false
//    
//    var body: some View {
//        VStack(spacing: 4) {
//            // Top Bar with Calibration and Time Delay
//            HStack {
//                // Calibration Button
//                Button(action: {
//                    // Calibration functionality to be added later
//                    print("Calibration tapped")
//                }) {
//                    Image(systemName: "scope")
//                        .font(.system(size: 18, weight: .medium))
//                        .foregroundColor(.blue)
//                        .frame(width: 36, height: 36)
//                        .background(
//                            Circle()
//                                .fill(Color.blue.opacity(0.1))
//                        )
//                }
//                .buttonStyle(PlainButtonStyle())
//                
//                Spacer()
//                
//                // Time Delay Button - Clock Icon that shows number on hover
//                Button(action: {
//                    // Cycle through: 5 -> 10 -> 15 -> 20 -> 25 -> 30 -> 5
//                    let currentValue = Int(motionManager.badPostureDuration)
//                    if currentValue >= 30 {
//                        motionManager.badPostureDuration = 5.0
//                    } else {
//                        motionManager.badPostureDuration = TimeInterval(currentValue + 5)
//                    }
//                }) {
//                    Group {
//                        if isHoveringTime {
//                            Text("\(Int(motionManager.badPostureDuration))")
//                                .font(.system(size: 16, weight: .semibold))
//                        } else {
//                            Image(systemName: "clock.fill")
//                                .font(.system(size: 18, weight: .medium))
//                        }
//                    }
//                    .foregroundColor(.orange)
//                    .frame(width: 36, height: 36)
//                    .background(
//                        Circle()
//                            .fill(Color.orange.opacity(0.1))
//                    )
//                }
//                .buttonStyle(PlainButtonStyle())
//                .onHover { hovering in
//                    isHoveringTime = hovering
//                }
//            }
//            .padding(.horizontal, 20)
//            .padding(.bottom, 20)
//            
//            // AirPods Image - Clickable
//            Button(action: {
//                motionManager.isTracking.toggle()
//            }) {
//                Image(systemName: "airpodspro")
//                    .font(.system(size: 120))
//                    .foregroundColor(motionManager.isTracking ? .blue : .gray)
//            }
//            .buttonStyle(PlainButtonStyle())
//            .padding(.bottom, 20)
//            
//            // Axis Title with letter spacing - more aesthetic
//            Text("AXIS")
//                .font(.system(size: 16, weight: .light))
//                .tracking(6)
//                .foregroundColor(.secondary)
//                .opacity(0.8)
//                .frame(maxWidth: .infinity)
//            
//            Spacer()
//                .frame(maxHeight: 20)
//        }
//        .frame(width: 280, height: 290)
//    }
//}
//
//struct BadPostureView: View {
//    let pitch: Int
//    
//    var body: some View {
//        VStack(spacing: 16) {
//            Image(systemName: "exclamationmark.triangle.fill")
//                .font(.system(size: 50))
//                .foregroundColor(.orange)
//            
//            Text("Bad Posture!")
//                .font(.title2)
//                .fontWeight(.bold)
//            
//            Text("Head tilted \(pitch)° forward")
//                .foregroundColor(.secondary)
//            
//            Text("Sit up straight")
//                .font(.caption)
//        }
//        .padding(30)
//    }
//}

