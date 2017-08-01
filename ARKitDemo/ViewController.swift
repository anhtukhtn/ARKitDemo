//
//  ViewController.swift
//  ARKitDemo
//
//  Created by anhtu on 8/1/17.
//  Copyright © 2017 anhtu. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
  // video capture session
  let session = AVCaptureSession()
  // preview layer
  var previewLayer: AVCaptureVideoPreviewLayer!
  // queue for processing video frames
  let captureQueue = DispatchQueue(label: "captureQueue")
  // overlay layer
  var gradientLayer: CAGradientLayer!
  // vision request
  var visionRequests = [VNRequest]()
  
  let rectangleDetection = VNDetectRectanglesRequest()
  let handler = VNSequenceRequestHandler()
  let shapeLayer = CAShapeLayer()
  
  var recognitionThreshold : Float = 0.25
  
  @IBOutlet weak var thresholdStackView: UIStackView!
  @IBOutlet weak var threshholdLabel: UILabel!
  @IBOutlet weak var threshholdSlider: UISlider!
  
  @IBOutlet weak var previewView: UIView!
  @IBOutlet weak var resultView: UILabel!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // get hold of the default video camera
    guard let camera = AVCaptureDevice.default(for: .video) else {
      fatalError("No video camera available")
    }
    do {
      // add the preview layer
      previewLayer = AVCaptureVideoPreviewLayer(session: session)
      previewView.layer.addSublayer(previewLayer)
      // add a slight gradient overlay so we can read the results easily
      gradientLayer = CAGradientLayer()
      gradientLayer.colors = [
        UIColor.init(red: 0, green: 0, blue: 0, alpha: 0.7).cgColor,
        UIColor.init(red: 0, green: 0, blue: 0, alpha: 0.0).cgColor,
      ]
      gradientLayer.locations = [0.0, 0.3]
      self.previewView.layer.addSublayer(gradientLayer)
      
      // create the capture input and the video output
      let cameraInput = try AVCaptureDeviceInput(device: camera)
      
      let videoOutput = AVCaptureVideoDataOutput()
      videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
      session.sessionPreset = .high
      
      // wire up the session
      session.addInput(cameraInput)
      session.addOutput(videoOutput)
      
      // make sure we are in portrait mode
      let conn = videoOutput.connection(with: .video)
      conn?.videoOrientation = .portrait
      
      // Start the session
      session.startRunning()
      
      // set up the vision model
      guard let resNet50Model = try? VNCoreMLModel(for: Resnet50().model) else {
        fatalError("Could not load model")
      }
      // set up the request using our vision model
      let classificationRequest = VNCoreMLRequest(model: resNet50Model, completionHandler: handleClassifications)
      classificationRequest.imageCropAndScaleOption = .centerCrop
      visionRequests = [classificationRequest]
      
      //        rectangleDetection.quadratureTolerance = 45
      rectangleDetection.maximumObservations = 50
    } catch {
      fatalError(error.localizedDescription)
    }
    
    updateThreshholdLabel()
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    //        guard let previewLayer = previewLayer else { return }
    
    //        view.layer.addSublayer(previewLayer)
    
    shapeLayer.strokeColor = UIColor.red.cgColor
    shapeLayer.lineWidth = 2.0
    
    //needs to filp coordinate system for Vision
    //        shapeLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: -1))
    
    previewView.layer.addSublayer(shapeLayer)
  }
  
  func updateThreshholdLabel () {
    self.threshholdLabel.text = "Threshold: " + String(format: "%.2f", recognitionThreshold)
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = self.previewView.bounds;
    gradientLayer.frame = self.previewView.bounds;
  }
  
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    
    connection.videoOrientation = .portrait
    
    var requestOptions:[VNImageOption: Any] = [:]
    
    if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
      requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
    }
    
    
    // for orientation see kCGImagePropertyOrientation
    let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored, options: requestOptions)
    do {
      try imageRequestHandler.perform(self.visionRequests)
    } catch {
      print(error)
    }
    
    let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate)
    let ciImage = CIImage(cvImageBuffer: pixelBuffer, options: attachments as! [String : Any]?)
    
    //leftMirrored for front camera
    let ciImageWithOrientation = ciImage.oriented(forExifOrientation: Int32(UIImageOrientation.leftMirrored.rawValue))
    
    detect(on: ciImageWithOrientation)
  }
  
  func detect(on image: CIImage) {
    try? handler.perform([rectangleDetection], on: image)
    if let results = rectangleDetection.results as? [VNRectangleObservation] {
      if !results.isEmpty {
        DispatchQueue.main.async {
          print(results.count)
          self.shapeLayer.sublayers?.removeAll()
          var biggestRect = results[0];
          var biggestDistance = CGFloat(0.0);
          for rect in results {
            let distance = (rect.bottomRight.x - rect.topLeft.x) + (rect.bottomRight.y - rect.topLeft.y);
            if distance > biggestDistance {
              biggestDistance = distance;
              biggestRect = rect;
            }
          }
          //                    for rect in results {
          //                        print(rect.confidence)
          if biggestRect.confidence > 0.5 {
            let transformedRect = biggestRect.boundingBox
            // transformedRect.origin.y = 1 - transformedRect.origin.y
            let convertedRect = self.previewLayer?.layerRectConverted(fromMetadataOutputRect: transformedRect)
            if let validRect = convertedRect {
              self.drawRect(rect: validRect)
            }
          }
          //                    }
        }
      }
    }
  }
  
  func drawRect(rect: CGRect) {
    let newLayer = CAShapeLayer()
    newLayer.strokeColor = UIColor.red.cgColor
    newLayer.lineWidth = 2.0
    newLayer.fillColor = UIColor.clear.cgColor
    
    let path = UIBezierPath(rect: rect)
    newLayer.path = path.cgPath
    
    shapeLayer.addSublayer(newLayer)
  }
  
  @IBAction func userTapped(sender: Any) {
    self.thresholdStackView.isHidden = !self.thresholdStackView.isHidden
  }
  
  @IBAction func sliderValueChanged(slider: UISlider) {
    self.recognitionThreshold = slider.value
    updateThreshholdLabel()
  }
  
  func handleClassifications(request: VNRequest, error: Error?) {
    if let theError = error {
      print("Error: \(theError.localizedDescription)")
      return
    }
    guard let observations = request.results else {
      print("No results")
      return
    }
    
    let classifications = observations[0...4] // top 4 results
      .flatMap({ $0 as? VNClassificationObservation })
      .flatMap({$0.confidence > recognitionThreshold ? $0 : nil})
      .map({ "\($0.identifier) \(String(format:"%.2f", $0.confidence))" })
      .joined(separator: "\n")
    
    observations[0...4] // top 4 results
      .flatMap({ $0 as? VNClassificationObservation })
      .flatMap({$0.confidence > recognitionThreshold ? $0 : nil}).forEach { (obj) in
        if obj.identifier.contains("cabinet") || obj.identifier.contains("closet") ||
          obj.identifier.contains("bag") {
          shapeLayer.isHidden = false
        }
        else {
          shapeLayer.isHidden = true
        }
    }
    
    
    DispatchQueue.main.async {
      self.resultView.text = classifications
    }
    
  }
}


