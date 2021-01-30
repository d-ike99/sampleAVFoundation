//
//  ViewController.swift
//  avFoundation
//
//  Created by 池田和浩 on 2020/12/12.
//

import UIKit
import AVFoundation

import CoreGraphics
import VideoToolbox

class ViewController: UIViewController {

    enum VideoCaptureError: Error {
        case captureSessionIsMissing
        case invalidInput
        case invalidOutput
        case unknown
    }
    
    // クラス部品
    private var currentFrame: CGImage!
    private var dispFrame: dispImageView!
    private var testView: UIImageView!
    
    // AVFoundationに関する部品
    var captureSession: AVCaptureSession! = nil
    var videoInput: AVCaptureDeviceInput! = nil
    var videoOutput: AVCaptureVideoDataOutput! = nil
    
    /// The dispatch queue responsible for processing camera set up and frame capture.
    private let sessionQueue = DispatchQueue(label: "com.example.apple-samplecode.estimating-human-pose-with-posenet.sessionqueue")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        // init
        self.dispFrame = dispImageView()
        dispFrame.frame = CGRect(x: 0, y: 0, width: 375, height: 550)
        dispFrame.isUserInteractionEnabled = true
        
        self.testView = UIImageView()
        testView.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: 550)
        
        self.view.backgroundColor = .white
        self.view.addSubview(dispFrame)
        self.view.isUserInteractionEnabled = true
        self.view.addSubview(testView)
        self.view.backgroundColor = .white
        
        print("dispWidth: ", self.view.frame.width as Any)
        print("dispHeight: ", self.view.frame.height as Any)
        
        // セッションの初期化
        self.setUpSession() { error in
            if let error = error {
                print("Failed to setup camera with error \(error)")
                return
            }
            // 動画撮影開始
            self.startCapturing()
        }
    }

    // 初期化
    private func setUpSession(completion: @escaping (Error?) -> Void) {
        do {
            // インプット、アウトプットの設定
            try self.initalizeAVFoundation()
            completion(nil)
            
        } catch {
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }
    
    private func startCapturing(completion completionHandler: (() -> Void)? = nil) {
        if !self.captureSession.isRunning {
            // Invoke the startRunning method of the captureSession to start the
            // flow of data from the inputs to the outputs.
            self.captureSession.startRunning()
        }
        
        print("captureStart")
        
        if let completionHandler = completionHandler {
            DispatchQueue.main.async {
                completionHandler()
            }
        }
    }
}

// セッションに関する、privateメソッドを管理する
extension ViewController {
    private func initalizeAVFoundation() throws {
        // 各種初期化
        self.captureSession = AVCaptureSession()
        
        // セッションの停止
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        
        self.captureSession.beginConfiguration()
        //self.captureSession.sessionPreset = .vga640x480
        self.captureSession.sessionPreset = .hd1280x720
        //self.captureSession.sessionPreset = .hd1920x1080
        
        // AVCaptureInputの定義
        try setCaptureSessionInput()

        // AVCaptureOutputの定義
        try setCaptureSessionOutput()

        captureSession.commitConfiguration()
    }
    
    // initialize AVCaptureInput
    private func setCaptureSessionInput() throws {
        // define inputDevice
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front) else {
            return
        }
        
        // セッションのインプット情報を削除する
        captureSession.inputs.forEach{ input in
            captureSession.removeInput(input)
        }
        
        // インプットの定義
        guard  let createInputInfo = try? AVCaptureDeviceInput(device: captureDevice) else {
            return
        }
        self.videoInput = createInputInfo
        //videoInput.ports(for: AVMediaType.video, sourceDeviceType: AVCaptureDevice.DeviceType.builtInDualCamera, sourceDevicePosition: AVCaptureDevice.Position.back)
        
        captureSession.addInput(self.videoInput)
    }
    // initialize AVCaptureOutput
    private func setCaptureSessionOutput() throws {
        // セッションのアウトプット情報を削除する
        captureSession.outputs.forEach { output in
            captureSession.removeOutput(output)
        }
        
        let settings: [String: Any] = [
                    String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
        // 初期化
        self.videoOutput = AVCaptureVideoDataOutput()
        
        self.videoOutput.videoSettings = settings
        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        //self.videoOutput.recommendedVideoSettings(forVideoCodecType: AVVideoCodecType.h264, assetWriterOutputFileType: AVFileType.mp4)
        //videoOutput.sampleBufferDelegate = self
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        
        print("sampleBufferDelegate", videoOutput.sampleBufferDelegate as Any)
        print("sampleBufferCallbackQueue", videoOutput.sampleBufferCallbackQueue as Any)
        print("availablezvideoCodecTypes: ", videoOutput.availableVideoCodecTypes as Any)
        
        guard captureSession.canAddOutput(videoOutput) else {
            throw VideoCaptureError.invalidOutput
        }
        captureSession.addOutput(self.videoOutput)
        
        // 動画の向き（orientation）の設定
        if let connection: AVCaptureConnection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation)
            connection.isVideoMirrored = true
            
            // Inverse the landscape orientation to force the image in the upward
            // orientation.
            if connection.videoOrientation == .landscapeLeft {
                connection.videoOrientation = .landscapeRight
            } else if connection.videoOrientation == .landscapeRight {
                connection.videoOrientation = .landscapeLeft
            }
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        defer {
            // Release `currentFrame` when exiting this method.
            self.currentFrame = nil
        }
        
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }
        
        // 画像生成
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return
        }
        
        var image: CGImage?
        
        // VideoToolbox
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        
        // CoreVideo
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        sessionQueue.sync {
            self.dispFrame(didCaptureFrame: image)
        }
    }
    // フレーム表示処理
    private func dispFrame(didCaptureFrame capturedImage: CGImage?){
        // 生成画像の反映
        guard currentFrame == nil else {
            return
        }
        
        // 以下どちらの方法でも表示可能
        self.testView.image = UIImage(cgImage: capturedImage!)
        //dispFrame.show(on: capturedImage!)
    }
}
 
