import Foundation
import AWSS3
import AWSClientRuntime
import AWSSDKIdentity

struct PostureSession: Codable {
    let timestamp: String
    let pitch: Double
    let roll: Double
    let status: String
}

struct PostureData: Codable {
    let userId: String
    var sessions: [PostureSession]
}

final class PostureLogger {
    static let shared = PostureLogger()
    private init() {}
    
    private let userId = "Colin"
    private var postureData = PostureData(userId: "Colin", sessions: [])
    
    private var lastUploadTime: Date = .distantPast
    private let uploadInterval: TimeInterval = 30
    
    private let env = ProcessInfo.processInfo.environment
    
    private let bucketName = ProcessInfo.processInfo.environment["S3_BUCKET_NAME"]
    private let region = ProcessInfo.processInfo.environment["AWS_DEFAULT_REGION"]
    
    private lazy var s3Client: S3Client = {
        let env = ProcessInfo.processInfo.environment

        guard
            let accessKey = env["AWS_ACCESS_KEY_ID"],
            let secret = env["AWS_SECRET_ACCESS_KEY"],
            let sessionToken = env["AWS_SESSION_TOKEN"]
        else {
            fatalError("AWS credentials not set in environment")
        }

        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secret,
                sessionToken: sessionToken
            )
            let provider = try StaticAWSCredentialIdentityResolver(credentials)
            let config = try S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: provider,
                region: region
            )
            return S3Client(config: config)

        } catch {
            fatalError("❌ Failed to configure S3 client: \(error)")
        }
    }()
    
    func startLogging() {
        Task {
            await loadExistingData()
            print("📊 Started logging posture sessions. Current count: \(postureData.sessions.count)")
        }
    }
    
    func logReading(pitch: Double, roll: Double, isGoodPosture: Bool) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let session = PostureSession(
            timestamp: timestamp,
            pitch: pitch,
            roll: roll,
            status: isGoodPosture ? "good" : "bad"
        )
        
        postureData.sessions.append(session)
        print("🪶 Logged posture: \(session.status.uppercased()) | pitch \(pitch), roll \(roll)")
        
        let now = Date()
        if now.timeIntervalSince(lastUploadTime) >= uploadInterval {
            lastUploadTime = now
            Task {
                await uploadToS3()
            }
        }
    }
    
    // MARK: - Private
    
    private func s3Key() -> String {
        return "posture/\(userId).json"
    }
    
    private func loadExistingData() async {
        let key = s3Key()
        let input = GetObjectInput(bucket: bucketName, key: key)
        
        do {
            let response = try await s3Client.getObject(input: input)
            
            if let body = response.body {
                // Convert ByteStream to Data
                if let data = try await body.readData() { // unwrap optional
                    let existingData = try JSONDecoder().decode(PostureData.self, from: data)
                    postureData.sessions = existingData.sessions
                    print("📥 Loaded \(existingData.sessions.count) previous sessions from S3")
                } else {
                    print("⚠️ No data in S3 object, starting fresh")
                    postureData.sessions = []
                }
            } else {
                print("⚠️ No body in S3 object, starting fresh")
                postureData.sessions = []
            }
        } catch {
            print("⚠️ No existing posture file found, starting fresh: \(error)")
            postureData.sessions = []
        }
    }
    
    func uploadToS3() async {
        do {
            let jsonData = try JSONEncoder().encode(postureData)
            let input = PutObjectInput(
                body: .data(jsonData),
                bucket: bucketName,
                contentType: "application/json",
                key: s3Key()
            )
            _ = try await s3Client.putObject(input: input)
            print("✅ Uploaded posture data to S3 (\(postureData.sessions.count) sessions)")
        } catch {
            print("❌ Failed to upload posture data: \(error)")
        }
    }
    
    
}
