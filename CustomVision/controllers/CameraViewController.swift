//
//  CameraViewController.swift
//  VirtualPyhsics
//
//  Created by Umut BOZ on 2.08.2018.
//  Copyright © 2018 Adam Behringer. All rights reserved.
//

import UIKit
import Vision
import AVFoundation


let context = CIContext()
var rotateTransform: CGAffineTransform?
var scaleTransform: CGAffineTransform?
var cropTransform: CGAffineTransform?
var resultBuffer: CVPixelBuffer?

class CameraViewController: UIViewController {
let targetImageSize = CGSize(width: 227, height: 227) // must match model data input
    // Live Camera Properties
    let queue = DispatchQueue(label: "videoQueue")
    var captureSession = AVCaptureSession()
    var captureDevice: AVCaptureDevice?
    let videoOutput = AVCaptureVideoDataOutput()
    var devicePosition: AVCaptureDevice.Position = .back
    
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var lowerView: UIView!
    @IBOutlet weak var previewView: UIView!
    let bubbleLayer = BubbleLayer(string: "")
    var maskLayer = [CAShapeLayer]()
    // MARK: Handle image classification results
    var probabiltyUnknownCounter = 0
    var unknownCounter = 0 // used to track how many unclassified images in a row
    let confidence: Float = 0.998
    var previewLayer: AVCaptureVideoPreviewLayer!
    
      lazy var classificationRequest: [VNRequest] = {
        do {
          // Load the Custom Vision model.
          // To add a new model, drag it to the Xcode project browser making sure that the "Target Membership" is checked.
          // Then update the following line with the name of your new model.
          let model = try VNCoreMLModel(for: cup().model)
          let classificationRequest = VNCoreMLRequest(model: model, completionHandler: self.handleClassification)
          return [classificationRequest ]
        } catch {
          fatalError("Can't load Vision ML model: \(error)")
        }
      }()
    

    func handleClassification(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNClassificationObservation]
            else { fatalError("unexpected result type from VNCoreMLRequest") }
        
        guard let best = observations.first else {
            fatalError("classification didn't return any results")
        }
        
        // Use results to update user interface (includes basic filtering)
        print("\(best.identifier): \(best.confidence)")
        if best.identifier.starts(with: "Unknown") || best.confidence < 0.9995 {
            self.probabiltyUnknownCounter = 0
            if self.unknownCounter < 3 { // a bit of a low-pass filter to avoid flickering
                self.unknownCounter += 1
            } else {
                self.unknownCounter = 0
                DispatchQueue.main.async {
                    self.bubbleLayer.string = nil
                    self.removeMask()
                }
            }
        } else {
            self.unknownCounter = 0
            
            let image = CameraViewController.imageBufferToUIImage(resultBuffer!)
            //FileOperations.saveFile(image: image)
            print(image.size)
            
            DispatchQueue.main.async {
                // if self.knownCounter >= 3{
                CustomVisionAI().upload(image: image, completionSuccess: { (response) in
                    
                    if best.confidence < 0.9995{
                        self.probabiltyUnknownCounter = 0
                        DispatchQueue.main.async {
                            self.bubbleLayer.string = nil
                            self.removeMask()
                            return
                        }
                        return
                    }
                    
                    let predictions = response.filter{$0.probability! > 0.75}
                    if predictions.count > 0 {
                        self.removeMask()
                        self.probabiltyUnknownCounter = 0
                        //drawing
                        predictions.forEach{ prediction in
                            let boundingBox = prediction.boundingBox
                            let rect = CGRect(
                                origin: CGPoint(x: (boundingBox?.left)!, y: (boundingBox?.top)!),
                                size: CGSize(width: (boundingBox?.width)!, height: (boundingBox?.height)!)
                            )
                            // let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewView.frame.height)
                            let translate = CGAffineTransform.identity.scaledBy(x: self.previewView.frame.width, y: self.previewView.frame.height)
                            let rectangleBounds = rect.applying(translate)
                            self.drawLayer(in: rectangleBounds)
                            
                        }
                    }else{
                        if self.probabiltyUnknownCounter < 3 {
                            self.probabiltyUnknownCounter += 1
                        }else{
                            self.probabiltyUnknownCounter = 0
                            DispatchQueue.main.async {
                                self.bubbleLayer.string = nil
                                self.removeMask()
                                return
                            }
                        }
                    }
                    //print("\(prediction)")
                    self.bubbleLayer.string = best.identifier.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                }) { (error) in
                    print("\(error)")
                }
                //}
                // Trimming labels because they sometimes have unexpected line endings which show up in the GUI
                
            }
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewView.layer.addSublayer(previewLayer)
        // Do any additional setup after loading the view.
    }
    override func viewDidAppear(_ animated: Bool) {
        
     setupCamera()
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    override func viewDidLayoutSubviews() {
         previewLayer.frame = previewView.bounds;
    }

    
    func removeMask() {
        for mask in maskLayer {
            mask.removeFromSuperlayer()
        }
        maskLayer.removeAll()
    }
    func drawLayer(in rect: CGRect) {
        //removeMask()
        
        let mask = CAShapeLayer()
        mask.frame = rect
        
        mask.backgroundColor = UIColor.clear.cgColor
        mask.cornerRadius = 10
        mask.opacity = 0.3
        mask.borderColor = UIColor.yellow.cgColor
        mask.borderWidth = 2.0
        
        maskLayer.append(mask)
        // previewLayer.insertSublayer(mask, at: 1)
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    
    /* TRANSFORM OPERASYONLARI */
    
    //                let probabilty : Double = (response.first?.probability)!
    //                print(probabilty)
    //                if  best.confidence >= 0.9995 && probabilty < 0.75 {
    //                    if self.probabiltyUnknownCounter < 3 {
    //                        self.probabiltyUnknownCounter += 1
    //                    } else {
    //                        self.probabiltyUnknownCounter += 0
    //                        DispatchQueue.main.async {
    //                            self.bubbleLayer.string = nil
    //                            self.removeMask()
    //                        }
    //                         return
    //                    }
    //                }
    //                let boundingBox = prediction?.boundingBox
    //                let rect = CGRect(
    //                    origin: CGPoint(x: (boundingBox?.left)!, y: (boundingBox?.top)!),
    //                    size: CGSize(width: (boundingBox?.width)!, height: (boundingBox?.height)!)
    //                )
    //                let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewView.frame.height)
    //                let translate = CGAffineTransform.identity.scaledBy(x: self.previewView.frame.width, y: self.previewView.frame.height)
    //                let rectangleBounds = rect.applying(translate).applying(transform)
    //
    //                self.drawLayer(in: rectangleBounds)
    
    //let transform2 = CGAffineTransform(scaleX: 0, y: 0).translatedBy(x: 0, y:self.previewView.frame.height)
    /* TRANSFORM OPERASYONLARI  END*/

}





