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
        dispFrame.frame = CGRect(x: 20, y: 20, width: self.view.frame.width - 40, height: self.view.frame.height - 40)
        dispFrame.isUserInteractionEnabled = true
        
        self.view.backgroundColor = .white
        self.view.addSubview(dispFrame)
        self.view.isUserInteractionEnabled = true
        
        // セッションの初期化
        self.setUpSession() { error in
            if let error = error {
                print("Failed to setup camera with error \(error)")
                return
            }
            // 動画撮影開始
            // 録音ボタン押下可能設定
            self.startCapturing()
        }
    }

    // 初期化
    public func setUpSession(completion: @escaping (Error?) -> Void) {
        sessionQueue.async {
            do {
                // インプット、アウトプットの設定
                try self.initalizeAVFoundation()
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    // 録音ボタン押下処理
    @objc func RecordTapped(_ sender: UITapGestureRecognizer) {
        self.startCapturing()
    }
    
    public func startCapturing(completion completionHandler: (() -> Void)? = nil) {
        sessionQueue.async {
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
        self.captureSession.sessionPreset = .vga640x480
        
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
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        
        guard captureSession.canAddOutput(videoOutput) else {
            throw VideoCaptureError.invalidOutput
        }
        captureSession.addOutput(self.videoOutput)
        
        // 動画の向き（orientation）の設定
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            print("test")
            
            connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.current.orientation.rawValue)!
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
        
        DispatchQueue.main.sync {
            self.dispFrame(didCaptureFrame: image)
        }
    }
    private func dispFrame(didCaptureFrame capturedImage: CGImage?){
        // 生成画像の反映
        guard currentFrame == nil else {
            return
        }
        dispFrame.show(on: capturedImage!)
    }
}
 
