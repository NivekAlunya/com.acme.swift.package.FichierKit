//
//  VLCPictureInPictureDrawableAdapter.swift
//  FichierKit
//
//  Bridges `VLCDrawable` and `VLCPictureInPictureDrawable` to a `UIView` render surface on iOS.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)
import UIKit
#if canImport(VLCKit)
import VLCKit

/// Adapter conforming to `VLCDrawable` and `VLCPictureInPictureDrawable` for a `UIView` render surface.
@MainActor
public final class VLCPictureInPictureDrawableAdapter: NSObject {
    private weak var renderView: UIView?
    private var pipWindowController: (any VLCPictureInPictureWindowControlling)?
    private let mediaControllerInstance = VLCPictureInPictureMediaController()

    /// Callback invoked on the main actor when Picture-in-Picture starts or stops.
    public var onPiPStateChanged: (@MainActor @Sendable (Bool) -> Void)?

    /// Indicates whether Picture-in-Picture presentation is currently active.
    public private(set) var isPiPActive: Bool = false

    /// Indicates whether VLCKit has provisioned a Picture-in-Picture window controller.
    public var isPiPReady: Bool {
        pipWindowController != nil
    }

    /// Creates a drawable adapter targeting the specified `UIView` and `VLCMediaPlayer`.
    public init(renderView: UIView, mediaPlayer: VLCMediaPlayer) {
        self.renderView = renderView
        self.mediaControllerInstance.mediaPlayer = mediaPlayer
        super.init()
    }

    /// Starts Picture-in-Picture playback if ready.
    public func startPictureInPicture() {
        guard let pipWindowController else { return }
        pipWindowController.invalidatePlaybackState()
        pipWindowController.startPictureInPicture()
    }

    /// Stops Picture-in-Picture playback if active.
    public func stopPictureInPicture() {
        pipWindowController?.stopPictureInPicture()
    }

    /// Toggles Picture-in-Picture playback between active and inline states.
    public func togglePictureInPicture() {
        if isPiPActive {
            stopPictureInPicture()
        } else {
            startPictureInPicture()
        }
    }

    /// Notifies the system Picture-in-Picture window that playback state or media duration changed.
    public func invalidatePlaybackState() {
        pipWindowController?.invalidatePlaybackState()
    }

    /// Resets cached PiP window state during engine teardown.
    public func resetPiPState() {
        if isPiPActive {
            pipWindowController?.stopPictureInPicture()
        }
        pipWindowController = nil
        isPiPActive = false
    }
}

extension VLCPictureInPictureDrawableAdapter: @MainActor VLCDrawable {
    public func addSubview(_ view: UIView!) {
        guard let view, let renderView else { return }
        renderView.addSubview(view)
        if renderView.bounds != .zero {
            view.frame = renderView.bounds
        }
    }

    public func bounds() -> CGRect {
        renderView?.bounds ?? .zero
    }
}

extension VLCPictureInPictureDrawableAdapter: @MainActor VLCPictureInPictureDrawable {
    public nonisolated func mediaController() -> (any VLCPictureInPictureMediaControlling)! {
        mediaControllerInstance
    }

    public nonisolated func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)! {
        { [weak self] pipController in
            let box = SendablePiPWindowControllerBox(controller: pipController)
            Task { @MainActor [weak self] in
                guard let self, let controller = box.controller else { return }
                self.pipWindowController = controller
                controller.stateChangeEventHandler = { [weak self] isStarted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.isPiPActive = isStarted
                        self.onPiPStateChanged?(isStarted)
                    }
                }
                controller.invalidatePlaybackState()
            }
        }
    }
}
#endif
#endif
