import AVFoundation
import Combine

enum MirrorCameraState {
    case off
    case requesting
    case running
    case stopping
    case denied
    case failed
}

final class MirrorCameraService: ObservableObject {
    @Published private(set) var state: MirrorCameraState = .off
    @Published private(set) var session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "BangBar.MirrorCameraService.session")
    private var isConfigured = false

    func toggle() {
        if state == .running || state == .requesting {
            stop()
        } else if state != .stopping {
            start()
        }
    }

    func start() {
        guard state != .requesting, state != .running, state != .stopping else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            state = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.state = .denied
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .failed
        }
    }

    func stop() {
        guard state == .running || state == .requesting else { return }
        state = .stopping

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async {
                self.resetSession()
                self.state = .off
            }
        }
    }

    private func configureAndStart() {
        state = .requesting

        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.configureSessionIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }

                DispatchQueue.main.async {
                    self.state = .running
                }
            } catch {
                self.session.stopRunning()

                DispatchQueue.main.async {
                    self.state = .failed
                }
            }
        }
    }

    private func resetSession() {
        isConfigured = false
        session = AVCaptureSession()
    }

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        else {
            throw MirrorCameraError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw MirrorCameraError.cannotAddInput
        }

        session.addInput(input)
        isConfigured = true
    }
}

private enum MirrorCameraError: Error {
    case noCamera
    case cannotAddInput
}
