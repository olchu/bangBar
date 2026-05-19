import SwiftUI
import AVFoundation
import AppKit

struct MirrorWidget: View {
    @ObservedObject var service: MirrorCameraService

    var body: some View {
        ZStack {
            if service.state == .running {
                CameraPreviewView(session: service.session)
                    .scaleEffect(x: -1, y: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: Color.white.opacity(0.10), radius: 10)
                    .transition(.scale(scale: 0.62).combined(with: .opacity))
            }

            if service.state == .running {
                Button(action: { service.toggle() }) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 23, height: 23)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(2)
            } else {
                Button(action: { service.toggle() }) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.045)
                                    ],
                                    center: .topLeading,
                                    startRadius: 4,
                                    endRadius: 34
                                )
                            )
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))

                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(iconColor)

                        statusDot
                            .offset(x: 16, y: -16)
                    }
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: service.state)
        .onDisappear {
            service.stop()
        }
    }

    private var iconName: String {
        switch service.state {
        case .off:
            return "video.fill"
        case .requesting:
            return "video.badge.ellipsis"
        case .running:
            return "video.fill"
        case .stopping:
            return "video.slash.fill"
        case .denied, .failed:
            return "video.slash.fill"
        }
    }

    private var iconColor: Color {
        switch service.state {
        case .denied, .failed:
            return .white.opacity(0.35)
        case .requesting, .stopping:
            return .white.opacity(0.55)
        case .off, .running:
            return .white.opacity(0.72)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch service.state {
        case .requesting, .stopping:
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 7, height: 7)
        case .denied, .failed:
            Circle()
                .fill(Color.red.opacity(0.72))
                .frame(width: 7, height: 7)
        case .off, .running:
            EmptyView()
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: CameraPreviewContainerView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class CameraPreviewContainerView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
