/*
The view controller for the Kaleidoscope camera interface.
*/

import UIKit
import AVFoundation
import CoreVideo
import Photos
import MobileCoreServices

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Properties

    @IBOutlet weak private var cameraButton: UIButton!

    @IBOutlet weak private var photoButton: UIButton!

    @IBOutlet weak private var resumeButton: UIButton!

    @IBOutlet weak private var cameraUnavailableLabel: UILabel!

    @IBOutlet weak private var previewView: PreviewMetalView!

    @IBOutlet weak private var renderingControlView : UIView!

    @IBOutlet weak private var brightnessSlider : UISlider!

    @IBOutlet weak private var transparencySlider : UISlider!

    private var kaleidoscopeFilterParams = KaleidoscopeFilterParams(
        numSegments: 3,
        mirrored: false,
        brightness: 0.8,
        transparency: 0.2,
        maxReflections: 64)

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    private var setupResult: SessionSetupResult = .success

    private let session = AVCaptureSession()

    private var isSessionRunning = false

    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "SessionQueue", attributes: [], autoreleaseFrequency: .workItem)

    private var videoInput: AVCaptureDeviceInput!

    private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)

    private let videoDataOutput = AVCaptureVideoDataOutput()

    private let photoOutput = AVCapturePhotoOutput()

    private var videoFilter: FilterRenderer = KaleidoscopeRenderer()

    private var photoFilter: FilterRenderer = KaleidoscopeRenderer()

    private var renderingEnabled = true

    private let processingQueue = DispatchQueue(label: "photo processing queue", attributes: [], autoreleaseFrequency: .workItem)

    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera],
        mediaType: .video,
        position: .unspecified)

    // On screen dots, marking the positions of mirror corners
    private var dotViews: [UIImageView] = []

    // View to hold all dotViews
    @IBOutlet private var dotView: UIView!

    // The current dot being dragged by the PanGesture
    private var draggingDot: UIView?

    // Positions of kaleidoscope mirrors
    private var mirrorCorners: [CGPoint]?

    // Bounding rect of video stream in screen coords
    private var currentVideoRect: CGRect?

    // Cached value of previewView.frame so any thread an query it
    private var previewViewFrame: CGRect?

    private enum UiControlMode {
        // Dots marking mirror corners can be dragged and re-positioned
        case draggableDots
        // Sliders to control rendering parameters
        case renderingSliders
        // All controls are hidden, best mode to enjoy results
        case controlsHidden
    }

    private var uiControlMode: UiControlMode = .draggableDots

    private var panGesture: UIPanGestureRecognizer?

    private var longPressPhotoGesture: UILongPressGestureRecognizer?

    private var clipRecorder: ClipRecorder?

    // MARK: - View Controller Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Disable UI. The UI is enabled if and only if the session starts running.
        cameraButton.isEnabled = false
        photoButton.isEnabled = false
        cameraUnavailableLabel.isHidden = true;
        resumeButton.isHidden = true;

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(cycleUiControlMode))
        previewView.addGestureRecognizer(tapGesture)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(dragDots))
        previewView.addGestureRecognizer(panGesture!)

        longPressPhotoGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressPhotoButton))
        photoButton.addGestureRecognizer(longPressPhotoGesture!)

        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break

        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant video access
             Suspend the SessionQueue to delay session setup until the access request has completed
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })

        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }

        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.

         Don't do this on the main queue, because AVCaptureSession.startRunning()
         is a blocking call, which can take a long time. Dispatch session setup
         to the sessionQueue so as not to block the main queue, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }

        let image = UIImage(named: "dot.png")
        let initialDotCoords = [[299, 302], [197, 200], [197, 443]]

        let dotSize = 24
        for coords in initialDotCoords {
            let imageView = UIImageView(image: image!)
            imageView.frame = CGRect(x: coords[0], y: coords[1],
                                     width: dotSize, height: dotSize)
            dotView.addSubview(imageView)
            dotViews.append(imageView)
        }

        renderingControlView.alpha = 0.0
        brightnessSlider.value = kaleidoscopeFilterParams.brightness
        transparencySlider.value = kaleidoscopeFilterParams.transparency

        // Cache this constant value to allow any thread to access it
        previewViewFrame = previewView.frame
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Prevent the device from sleeping.
        UIApplication.shared.isIdleTimerDisabled = true

        let initialThermalState = ProcessInfo.processInfo.thermalState
        if initialThermalState == .serious || initialThermalState == .critical {
            showThermalState(state: initialThermalState)
        }

        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.addObservers()

                if let unwrappedPhotoOutputConnection = self.photoOutput.connection(with: .video) {
                    unwrappedPhotoOutputConnection.videoOrientation = .portrait
                }
                self.previewView.mirroring = (self.videoInput.device.position == .front)
                self.previewView.rotation = .rotate90Degrees
                self.dataOutputQueue.async {
                    self.renderingEnabled = true
                }
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning

            case .notAuthorized:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Kaleidoscope doesn't have permission to use the camera, please change privacy settings",
                                                    comment: "Alert message when the user has denied access to the camera")
                    let actions = [
                        UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                      style: .cancel,
                                      handler: nil),
                        UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                      style: .`default`,
                                      handler: { _ in
                                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                  options: [:],
                                                                  completionHandler: nil)
                        })
                    ]

                    self.alert(title: "Kaleidoscope", message: message, actions: actions)
                }

            case .configurationFailed:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to capture media",
                                                    comment: "Alert message when something goes wrong during capture session configuration")
                    self.alert(title: "Kaleidoscope",
                               message: message,
                               actions: [UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                       style: .cancel,
                                                       handler: nil)])
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        dataOutputQueue.async {
            self.renderingEnabled = false
        }
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }

        // Allow the device to sleep.
        UIApplication.shared.isIdleTimerDisabled = false

        super.viewWillDisappear(animated)
    }

    @objc
    func didEnterBackground(notification: NSNotification) {
        // Free up resources.
        dataOutputQueue.async {
            self.renderingEnabled = false
            self.videoFilter.reset()
            self.previewView.pixelBuffer = nil
            self.previewView.flushTextureCache()
        }
        processingQueue.async {
            self.photoFilter.reset()
        }
    }

    @objc
    func willEnterForground(notification: NSNotification) {
        dataOutputQueue.async {
            self.renderingEnabled = true
        }
    }

    // Use this opportunity to take corrective action to help cool the system down.
    @objc
    func thermalStateChanged(notification: NSNotification) {
        if let processInfo = notification.object as? ProcessInfo {
            showThermalState(state: processInfo.thermalState)
        }
    }

    func showThermalState(state: ProcessInfo.ThermalState) {
        DispatchQueue.main.async {
            var thermalStateString = "UNKNOWN"
            if state == .nominal {
                thermalStateString = "NOMINAL"
            } else if state == .fair {
                thermalStateString = "FAIR"
            } else if state == .serious {
                thermalStateString = "SERIOUS"
            } else if state == .critical {
                thermalStateString = "CRITICAL"
            }

            let message = NSLocalizedString("Thermal state: \(thermalStateString)", comment: "Alert message when thermal state has changed")
            let actions = [
                UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                              style: .cancel,
                              handler: nil)]

            self.alert(title: "Kaleidoscope", message: message, actions: actions)
        }
    }

    // MARK: - KVO and Notifications

    private var sessionRunningContext = 0

    private func addObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(willEnterForground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: NSNotification.Name.AVCaptureSessionRuntimeError,
                                               object: session)

        session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.new, context: &sessionRunningContext)

        // A session can run only when the app is full screen. It will be interrupted in a multi-app layout.
        // Add observers to handle these session interruptions and inform the user.
        // See AVCaptureSessionWasInterruptedNotification for other interruption reasons.

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: NSNotification.Name.AVCaptureSessionWasInterrupted,
                                               object: session)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: NSNotification.Name.AVCaptureSessionInterruptionEnded,
                                               object: session)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        session.removeObserver(self, forKeyPath: "running", context: &sessionRunningContext)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &sessionRunningContext {
            let newValue = change?[.newKey] as AnyObject?
            guard let isSessionRunning = newValue?.boolValue else { return }
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = (isSessionRunning && self.videoDeviceDiscoverySession.devices.count > 1)
                self.photoButton.isEnabled = isSessionRunning
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - Session Management

    // Call this on the SessionQueue
    private func configureSession() {
        if setupResult != .success {
            return
        }

        let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first

        guard let videoDevice = defaultVideoDevice else {
            print("Could not find any video device")
            setupResult = .configurationFailed
            return
        }

        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            return
        }

        session.beginConfiguration()

        session.sessionPreset = AVCaptureSession.Preset.photo

        // Add a video input.
        guard session.canAddInput(videoInput) else {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)

        // Add a video data output
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]  // TODO(spor): play with this :)
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        } else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            photoOutput.isHighResolutionCaptureEnabled = true

        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        capFrameRate(videoDevice: videoDevice)

        session.commitConfiguration()

        updateImageRect(videoDevice)

        dataOutputQueue.async {
            self.videoFilter.reset()
            self.photoFilter.reset()
        }
    }

    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")

            if reason == .videoDeviceInUseByAnotherClient {
                // Simply fade-in a button to enable the user to try to resume the session running.
                resumeButton.isHidden = false
                resumeButton.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1.0
                }
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                cameraUnavailableLabel.isHidden = false
                cameraUnavailableLabel.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1.0
                }
            }
        }
    }

    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            }
            )
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
    }

    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }

        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")

        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }

    @IBAction private func resumeInterruptedSession(_ sender: UIButton) {
        sessionQueue.async {
            /*
             The session might fail to start running. A failure to start the session running will be communicated via
             a session runtime error notification. To avoid repeatedly failing to start the session
             running, we only try to restart the session running in the session runtime error handler
             if we aren't trying to resume the session running.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let actions = [
                        UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                      style: .cancel,
                                      handler: nil)]
                    self.alert(title: "Kaleidoscope", message: message, actions: actions)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }

    // MARK: - IBAction Functions

    @IBAction private func cycleUiControlMode(_ gesture: UITapGestureRecognizer) {
        switch uiControlMode {
        case .draggableDots:
            uiControlMode = .renderingSliders
        case .renderingSliders:
            uiControlMode = .controlsHidden
        case .controlsHidden:
            uiControlMode = .draggableDots
        }

        UIView.animate(withDuration: 0.25, animations: {
            self.dotView.alpha = self.uiControlMode == .draggableDots ? 1.0 : 0.0
            self.renderingControlView.alpha = self.uiControlMode == .renderingSliders ? 1.0 : 0.0
        })
    }

    @IBAction private func longPressPhotoButton(_ gesture: UILongPressGestureRecognizer) {
        switch (gesture.state) {
        case .began:
            let success = startRecordingClip()
            if success {
                photoButton.tintColor = .systemRed
            } else {
                gesture.state = .cancelled
            }

        case .cancelled, .ended:
            photoButton.tintColor = .systemOrange
            stopRecordingClip()

        default: break
        }
    }

    private func startRecordingClip() -> Bool {
        print ("start recording clip")
        clipRecorder = ClipRecorder()
        return clipRecorder != nil
    }

    private func stopRecordingClip() {
        print("stop recording clip")
        guard let unwrappedClipRecorder = clipRecorder else {
            print("no recording")
            return
        }

        unwrappedClipRecorder.stopRecording()
        clipRecorder = nil
    }

    @IBAction private func dragDots(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard uiControlMode == .draggableDots else {
                gesture.state = .cancelled
                return
            }
            var distances: [Float] = []
            for dot in dotViews {
                var pos = gesture.location(in: dot)
                pos.x -= dot.frame.width / 2;
                pos.y -= dot.frame.height / 2;
                let dist = sqrt(pos.x * pos.x + pos.y * pos.y)
                distances.append(Float(dist))
            }
            let minDistance = distances.min()
            let minIndex = distances.indices.filter{ distances[$0] == minDistance }

            // If gesture is this close to dot, drag it
            let closeEnough: Float = 25.0
            guard minDistance! < closeEnough, minIndex.count >= 1 else {
                gesture.state = .cancelled
                return
            }
            draggingDot = dotViews[minIndex[0]]

        case .changed:
            guard let unwrappedDraggingDot = draggingDot else {
                gesture.state = .cancelled
                return
            }

            let translation = gesture.translation(in: unwrappedDraggingDot)
            unwrappedDraggingDot.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
            updateMirrorCorners()

        case .ended:
            guard let unwrappedDraggingDot = draggingDot else {
                return
            }
            guard let videoRect = currentVideoRect else {
                print ("videoRect unset")
                return
            }
            // Reset the dot's frame after resetting its transform, so next drag event will work properly
            var translatedFrame = unwrappedDraggingDot.frame
            translatedFrame.origin.x = max(translatedFrame.origin.x, videoRect.origin.x)
            translatedFrame.origin.y = max(translatedFrame.origin.y, videoRect.origin.y)
            translatedFrame.origin.x = min(translatedFrame.origin.x,
                                           videoRect.origin.x + videoRect.width - translatedFrame.width)
            translatedFrame.origin.y = min(translatedFrame.origin.y,
                                           videoRect.origin.y + videoRect.height - translatedFrame.height)
            unwrappedDraggingDot.transform = .identity
            unwrappedDraggingDot.frame = translatedFrame
            updateMirrorCorners()

            draggingDot = .none

        default:
            gesture.state = .cancelled
        }
    }

    @IBAction private func changeBrightnessSlider(_ sender: UISlider) {
        kaleidoscopeFilterParams.brightness = sender.value
    }

    @IBAction private func changeTransparencySlider(_ sender: UISlider) {
        kaleidoscopeFilterParams.transparency = sender.value
    }

    @IBAction private func changeCamera(_ sender: UIButton) {
        cameraButton.isEnabled = false
        photoButton.isEnabled = false

        dataOutputQueue.sync {
            renderingEnabled = false
            videoFilter.reset()
            previewView.pixelBuffer = nil
        }

        processingQueue.async {
            self.photoFilter.reset()
        }

        sessionQueue.async {
            let currentVideoDevice = self.videoInput.device
            var preferredPosition = AVCaptureDevice.Position.unspecified
            switch currentVideoDevice.position {
            case .unspecified, .front:
                preferredPosition = .back

            case .back:
                preferredPosition = .front
            @unknown default:
                fatalError("Unknown video device position.")
            }

            let devices = self.videoDeviceDiscoverySession.devices
            if let videoDevice = devices.first(where: { $0.position == preferredPosition }) {
                var videoInput: AVCaptureDeviceInput
                do {
                    videoInput = try AVCaptureDeviceInput(device: videoDevice)
                } catch {
                    print("Could not create video device input: \(error)")
                    self.dataOutputQueue.async {
                        self.renderingEnabled = true
                    }
                    return
                }
                self.session.beginConfiguration()

                // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
                self.session.removeInput(self.videoInput)

                if self.session.canAddInput(videoInput) {
                    NotificationCenter.default.removeObserver(self,
                                                              name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange,
                                                              object: currentVideoDevice)

                    self.session.addInput(videoInput)
                    self.videoInput = videoInput
                } else {
                    print("Could not add video device input to the session")
                    self.session.addInput(self.videoInput)
                }

                if let unwrappedPhotoOutputConnection = self.photoOutput.connection(with: .video) {
                    self.photoOutput.connection(with: .video)!.videoOrientation = unwrappedPhotoOutputConnection.videoOrientation
                }

                self.session.commitConfiguration()

                self.updateImageRect(videoDevice)
            }

            self.previewView.mirroring = (self.videoInput.device.position == .front)

            self.dataOutputQueue.async {
                self.renderingEnabled = true
            }

            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.photoButton.isEnabled = true
            }
        }
    }

    @IBAction private func capturePhoto(_ photoButton: UIButton) {
        sessionQueue.async {
            let photoSettings = AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    // MARK: - Video Data Output Delegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processVideo(sampleBuffer: sampleBuffer)
    }

    func updateImageRect(_ device: AVCaptureDevice) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        print("updated video dimensions: \(String(describing: dimensions))")

        guard let unwrappedPreviewViewFrame = previewViewFrame else {
            return
        }
        currentVideoRect = unwrappedPreviewViewFrame
        
        // Widths and Heights are switched around due to portrait orientation assumption
        let imageAspectRatio = Float(dimensions.width) / Float(dimensions.height)
        let viewWidth = currentVideoRect!.size.width
        let viewHeight = currentVideoRect!.size.height
        let viewAspectRatio = Float(viewHeight) / Float(viewWidth)
        if (viewAspectRatio > imageAspectRatio) {
            // view is taller than image
            let crop = Float(viewHeight) * (viewAspectRatio - imageAspectRatio) / viewAspectRatio
            currentVideoRect!.origin.y += CGFloat(crop / 2)
            currentVideoRect!.size.height -= CGFloat(crop)
        } else {
            // view is wider than image
            let crop = Float(viewWidth) * (1.0 / viewAspectRatio - 1.0 / imageAspectRatio) / (1.0 / viewAspectRatio)
            currentVideoRect!.origin.x += CGFloat(crop / 2)
            currentVideoRect!.size.width -= CGFloat(crop)
        }

        DispatchQueue.main.async {
            self.updateMirrorCorners()
        }
    }

    func updateMirrorCorners() {
        guard let videoRect = currentVideoRect else {
            print ("videoRect unset")
            return
        }
        var corners: [CGPoint] = []

        for dot in dotViews {
            // TODO: fix this in case view is wider than image, currently broken
            var point = CGPoint(x: CGFloat(dot.frame.origin.x), y: CGFloat(dot.frame.origin.y))
            point.x += dot.frame.width / 2 - videoRect.origin.x
            point.y += dot.frame.height / 2 - videoRect.origin.y

            let corner = CGPoint(x: CGFloat(point.y / videoRect.size.height),
                                 y: CGFloat((videoRect.size.width - point.x) / videoRect.size.height))
            corners.append(corner)
        }
        mirrorCorners = corners
    }

    func setFilterParams(_ filter: FilterRenderer) {
        guard let renderer = filter as? KaleidoscopeRenderer else {
            return
        }

        kaleidoscopeFilterParams.mirrored = previewView.mirroring
        renderer.filterParams = kaleidoscopeFilterParams

        guard let unwrappedMirrorCorners = mirrorCorners else {
            print("mirrorCorners unset")
            return
        }
        renderer.mirrorCorners = unwrappedMirrorCorners
    }

    func processVideo(sampleBuffer: CMSampleBuffer) {
        if !renderingEnabled {
            return
        }

        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                return
        }

        var finalVideoPixelBuffer = videoPixelBuffer
        if !videoFilter.isPrepared {
            /*
             outputRetainedBufferCountHint is the number of pixel buffers the renderer retains. This value informs the renderer
             how to size its buffer pool and how many pixel buffers to preallocate. Allow 3 frames of latency to cover the dispatch_async call.
             */
            videoFilter.prepare(with: formatDescription, outputRetainedBufferCountHint: 3)
        }

        setFilterParams(videoFilter)

        // Send the pixel buffer through the filter
        guard let filteredBuffer = videoFilter.render(pixelBuffer: finalVideoPixelBuffer) else {
            print("Unable to filter video buffer")
            return
        }

        finalVideoPixelBuffer = filteredBuffer

        previewView.pixelBuffer = finalVideoPixelBuffer

        if let unwrappedClipRecorder = clipRecorder {
            unwrappedClipRecorder.appendBuffer(finalVideoPixelBuffer, withTimestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            print("bufferCount: \(unwrappedClipRecorder.bufferCount) recordDuration: \(CMTimeGetSeconds(unwrappedClipRecorder.recordDuration))")
        }
    }

    // MARK: - Photo Output Delegate
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        flashScreen()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let photoPixelBuffer = photo.pixelBuffer else {
            print("Error occurred while capturing photo: Missing pixel buffer (\(String(describing: error)))")
            return
        }

        var photoFormatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: photoPixelBuffer,
                                                     formatDescriptionOut: &photoFormatDescription)

        processingQueue.async {
            var finalPixelBuffer = photoPixelBuffer
            if !self.photoFilter.isPrepared {
                if let unwrappedPhotoFormatDescription = photoFormatDescription {
                    self.photoFilter.prepare(with: unwrappedPhotoFormatDescription, outputRetainedBufferCountHint: 2)
                }
            }

            self.setFilterParams(self.photoFilter)

            guard let filteredPixelBuffer = self.photoFilter.render(pixelBuffer: finalPixelBuffer) else {
                print("Unable to filter photo buffer")
                return
            }
            finalPixelBuffer = filteredPixelBuffer

            let metadataAttachments: CFDictionary = photo.metadata as CFDictionary
            guard let jpegData = CameraViewController.jpegData(withPixelBuffer: finalPixelBuffer, attachments: metadataAttachments) else {
                print("Unable to create JPEG photo")
                return
            }

            // Save JPEG to photo library
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo, data: jpegData, options: nil)
                    }, completionHandler: { _, error in
                        if let error = error {
                            print("Error occurred while saving photo to photo library: \(error)")
                        }
                    })
                }
            }
        }
    }

    // MARK: - Utilities
    private func capFrameRate(videoDevice: AVCaptureDevice) {
        if self.photoOutput.isDepthDataDeliverySupported {
            // Cap the video framerate at the max depth framerate.
            if let frameDuration = videoDevice.activeDepthDataFormat?.videoSupportedFrameRateRanges.first?.minFrameDuration {
                do {
                    try videoDevice.lockForConfiguration()
                    videoDevice.activeVideoMinFrameDuration = frameDuration
                    videoDevice.unlockForConfiguration()
                } catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        }
    }

    func alert(title: String, message: String, actions: [UIAlertAction]) {
        let alertController = UIAlertController(title: title,
                                                message: message,
                                                preferredStyle: .alert)

        actions.forEach {
            alertController.addAction($0)
        }

        self.present(alertController, animated: true, completion: nil)
    }

    // Flash the screen to signal that Kaleidoscope took a photo.
    func flashScreen() {
        let flashView = UIView(frame: self.previewView.frame)
        self.view.addSubview(flashView)
        flashView.backgroundColor = .black
        flashView.layer.opacity = 1
        UIView.animate(withDuration: 0.25, animations: {
            flashView.layer.opacity = 0
        }, completion: { _ in
            flashView.removeFromSuperview()
        })
    }

    private class func jpegData(withPixelBuffer pixelBuffer: CVPixelBuffer, attachments: CFDictionary?) -> Data? {
        let ciContext = CIContext()
        let renderedCIImage = CIImage(cvImageBuffer: pixelBuffer)
        guard let renderedCGImage = ciContext.createCGImage(renderedCIImage, from: renderedCIImage.extent) else {
            print("Failed to create CGImage")
            return nil
        }

        guard let data = CFDataCreateMutable(kCFAllocatorDefault, 0) else {
            print("Create CFData error!")
            return nil
        }

        guard let cgImageDestination = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil) else {
            print("Create CGImageDestination error!")
            return nil
        }

        CGImageDestinationAddImage(cgImageDestination, renderedCGImage, attachments)
        if CGImageDestinationFinalize(cgImageDestination) {
            return data as Data
        }
        print("Finalizing CGImageDestination error!")
        return nil
    }
}
