import UIKit
import AVFoundation
import Vision
import ARKit
import RxSwift
import RxCocoa
import Async

// controlling the pace of the machine vision analysis
var lastAnalysis: TimeInterval = 0
var pace: TimeInterval = 0.33 // in seconds, classification will not repeat faster than this value

// performance tracking
let trackPerformance = false // use "true" for performance logging
var frameCount = 0
let framesPerSample = 10
var startDate = NSDate.timeIntervalSinceReferenceDate

//Controller
class ViewController: UIViewController {
  //ARKit members
  @IBOutlet weak var sceneView: ARSCNView!
  var bounds: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
  var maskLayer = [CAShapeLayer]()
  @IBOutlet weak var stackView: UIStackView!
  let bubbleLayer = BubbleLayer(string: "")
  var 👜 = DisposeBag()
  var arCamInitializingIsOk : Bool = false

  internal var surfaceNodes = [ARPlaneAnchor:SurfaceNode]()
  

  // MARK: Handle image classification results
  var probabiltyUnknownCounter = 0
  var unknownCounter = 0 // used to track how many unclassified images in a row
  let confidence: Float = 0.998
  
  // MARK: Load the Model
  let cupModel :  VNCoreMLModel = try! VNCoreMLModel(for: cup().model)
  let targetImageSize = CGSize(width: 227, height: 227) // must match model data input
  let orient = UIApplication.shared.statusBarOrientation

  var cups: [SCNNode] = []
  // MARK: Lifecycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    sceneView.delegate = self
    sceneView.autoenablesDefaultLighting = true
    bounds = sceneView.bounds
    // Create a new scene
    let scene = SCNScene()
    
    // Set the scene to the view
    sceneView.scene = scene
  }
    override func viewWillAppear(_ animated: Bool) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)
        
        Observable<Int>.interval(0.6, scheduler: SerialDispatchQueueScheduler(qos: .default))
            .subscribeOn(SerialDispatchQueueScheduler(qos: .background))
            .concatMap{ _ in  self.cupObservation() }
            .flatMap{ Observable.from($0)}
            .flatMap{ self.cupClassification(cup: $0.observation, image: $0.image, frame: $0.frame,buffer: $0.buffer) }
            .subscribe { [unowned self] event in
                guard let element = event.element else {
                    print("No element available")
                    return
                }
                self.updateNode(classes: element.classes, position: element.position, frame: element.frame, buffer: element.buffer)
            }.disposed(by: 👜)
        
    }
   
    private func cupObservation() -> Observable<[(observation: VNRectangleObservation, image: CIImage, frame: ARFrame, buffer:CVPixelBuffer)]> {
        return Observable<[(observation: VNRectangleObservation, image: CIImage, frame: ARFrame, buffer: CVPixelBuffer)]>.create{ observer in
            if !self.arCamInitializingIsOk{
                print("Not arCamInitializingNot OK")
                observer.onCompleted()
                return Disposables.create()
            }
            
            guard let frame = self.sceneView.session.currentFrame else {
                print("No frame available")
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Create and rotate image
            //let image = CIImage.init(cvPixelBuffer: frame.capturedImage).rotate
            let pixbuff : CVPixelBuffer? = (frame.capturedImage)
            if pixbuff == nil {
                print("No CVPixelBuffer available")
                observer.onCompleted()
                return Disposables.create()
            }
            let ciImage = CIImage(cvPixelBuffer: pixbuff!).rotate
            let resizeBuffer = ciImage.convertUIImage().pixelBuffer(width: Int(self.targetImageSize.width), height: Int(self.targetImageSize.height))
        
            let rectRequest = VNDetectRectanglesRequest { request, error in
                guard error == nil else {
                    print("Face request error: \(error!.localizedDescription)")
                    observer.onCompleted()
                    return
                }
                guard let observations = request.results as? [VNRectangleObservation] else {
                    print("No face observations")
                    observer.onCompleted()
                    return
                }
                // Map response
                let response = observations.map({ (cup) -> (observation: VNRectangleObservation, image: CIImage, frame: ARFrame,buffer:CVPixelBuffer) in
                    return (observation: cup, image: ciImage, frame: frame, buffer: resizeBuffer!)
                })
                observer.onNext(response)
                observer.onCompleted()
            }
     
            do {
                let classifierRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
                //let classifierRequestHandler = VNImageRequestHandler(cvPixelBuffer: croppedBuffer, options: [:])
                try classifierRequestHandler.perform([rectRequest])
            } catch {
                print(error)
            }
            
            
            observer.onCompleted()
        return Disposables.create()
        }
    }
    
    private func cupClassification(cup: VNRectangleObservation, image: CIImage, frame: ARFrame,buffer: CVPixelBuffer) -> Observable<(classes: [VNClassificationObservation], position: SCNVector3, frame: ARFrame,buffer: CVPixelBuffer)> {
        return Observable<(classes: [VNClassificationObservation], position: SCNVector3, frame: ARFrame, buffer: CVPixelBuffer)>.create{ observer in
            // Determine position of the face
            let boundingBox = self.transformBoundingBox(cup.boundingBox)
            guard let worldCoord = self.normalizeWorldCoord(boundingBox) else {
                print("No feature point found")
                self.clearScreenRectangle()
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Create Classification request
            let request = VNCoreMLRequest(model: self.cupModel, completionHandler: { request, error in
                guard error == nil else {
                    print("ML request error: \(error!.localizedDescription)")
                    observer.onCompleted()
                    return
                }
                
                guard let classifications = request.results as? [VNClassificationObservation] else {
                    print("No classifications")
                    observer.onCompleted()
                    return
                }
                
                observer.onNext((classes: classifications, position: worldCoord, frame: frame, buffer: buffer))
                observer.onCompleted()
            })
            request.imageCropAndScaleOption = .scaleFit
            
            do {
         
//                let imageFromArkitScene:UIImage? = self.sceneView.snapshot()
//                FileOperations.saveFile(image: imageFromArkitScene!)
//
//                let capturedImage =  image.convertUIImage()
//                FileOperations.saveFile(image: capturedImage)
                
                //let resizeBuffer = image.convertUIImage().pixelBuffer(width: Int(self.targetImageSize.width), height: Int(self.targetImageSize.height))
                
//                let image2 = UIImage.init(pixelBuffer: resizeBuffer!)
//                FileOperations.saveFile(image: image2!)
                let resizeNewCIImage = CIImage.init(cvPixelBuffer: buffer)
                //FileOperations.saveFile(image: resizeNewCIImage.convertUIImage())
                //FileOperations.saveFile(image: UIImage.init(pixelBuffer: buffer)!)
                try VNImageRequestHandler(ciImage: resizeNewCIImage, options: [:]).perform([request])
            } catch {
                print("ML request handler error: \(error.localizedDescription)")
                observer.onCompleted()
            }
            return Disposables.create()
        }
    }

    private func updateNode(classes: [VNClassificationObservation], position: SCNVector3, frame: ARFrame, buffer: CVPixelBuffer) {
    
    guard let best = classes.first else {
        fatalError("classification didn't return any results")
    }
    
    // Use results to update user interface (includes basic filtering)
    print("\(best.identifier): \(best.confidence)")
    if best.identifier.starts(with: "Unknown") || best.confidence < 0.999511 {
        self.probabiltyUnknownCounter = 0
        if self.unknownCounter < 2 { // a bit of a low-pass filter to avoid flickering
            self.unknownCounter += 1
        } else {
            self.unknownCounter = 0
            self.clearScreenRectangle()
        }
    }
    else{
        self.unknownCounter = 0
        let uploadImage = UIImage.init(pixelBuffer: buffer)
        Async.main {
            CustomVisionAI().upload(image: uploadImage!, completionSuccess: { (response) in
                if best.confidence < 1{
                    self.probabiltyUnknownCounter = 0
                    self.clearScreenRectangle()
                    return
                }
                let predictions = response.filter{$0.probability! > 0.75}
                if predictions.count > 0 {
                    //self.removeNodes()
                    //self.removeMask()
                    self.probabiltyUnknownCounter = 0
                    //drawing
                    predictions.forEach{ prediction in
                        let boundingBox = prediction.boundingBox
                        let rect = CGRect(
                            origin: CGPoint(x: (boundingBox?.left)!, y: (boundingBox?.top)!),
                            size: CGSize(width: (boundingBox?.width)!, height: (boundingBox?.height)!)
                        )
                        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.sceneView.frame.height)
                        let translate = CGAffineTransform.identity.scaledBy(x: self.sceneView.frame.width, y: self.sceneView.frame.height)
                        let rectangleBounds = rect.applying(translate)
                        self.drawLayer(in: rectangleBounds)
                        print("\(prediction.probability)")
                        
                       // let transformBoundingBox = self.transformBoundingBox(rectangleBounds)
                       // let worldCoord = self.normalizeWorldCoord(transformBoundingBox)
                        
                        guard let worldCoord = self.normalizeWorldCoord(rectangleBounds) else {
                            print("No feature point found")
                          return
                        }
                        let hasSameDistanceVector = self.hasSameDistance(position: worldCoord)
                        if hasSameDistanceVector{
                            return
                        }
                        let node = SCNNode.init(withText: "cup", position: worldCoord)

                        Async.main {
                            self.sceneView.scene.rootNode.addChildNode(node)
                            self.cups.append(node)
                            self.cups.forEach{ (cup) in
                                cup.show()
                            }
                        }
                    }
                }else{
                    if self.probabiltyUnknownCounter < 2 {
                        self.probabiltyUnknownCounter += 1
                    }else{
                        self.probabiltyUnknownCounter = 0
                        self.clearScreenRectangle()
                        return
                    }
                }
            }, completionError: { (error) in
                 print("\(error)")
                 self.clearScreenRectangle()
            })
        }
    }
  }
    
    
    func removeNodes() {
        self.cups.forEach{ cup in
            
            cup.removeFromParentNode()
            
        }
    }
    func hasSameDistance(position: SCNVector3) -> Bool {
        var hasSameDistance = false
        for cup in self.cups {
            let distance = cup.position.distance(toVector: position)
            print("distance :\(distance)")
            if distance < 0.1{
                hasSameDistance = true
                print("has same distance :\(distance)")
                break
            }
        }
        return hasSameDistance
    }
    func clearScreenRectangle() {
        Async.main {
            self.bubbleLayer.string = nil
            self.removeMask()
            //self.removeNodes()
            
        }
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
        self.sceneView.layer.insertSublayer(mask, at: 1)
        //self.sceneView.insertSubview(mask, at: 1)
        // previewLayer.insertSublayer(mask, at: 1)
    
    }
  override func viewDidAppear(_ animated: Bool) {
    bubbleLayer.opacity = 0.0
    bubbleLayer.position.x = self.view.frame.width / 2.0
    bubbleLayer.position.y = self.view.frame.height / 2
    self.view.layer.addSublayer(bubbleLayer)
   
  }
    
    override func viewWillDisappear(_ animated: Bool) {
        sceneView.session.pause()
       👜 = DisposeBag()
    }
    
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
   
  }
    
    
    func addPlaneRect(for observedRect: VNRectangleObservation) {
    
        
       // let rectangleNode = RectangleNode(planeRectangle)
        
        //self.sceneView.scene.rootNode.addChildNode(rectangleNode)
    }
    
    func addSurfaceRactangleNode(anchor:ARAnchor) {
        guard let anchor = anchor as? ARPlaneAnchor else {
            return
        }
        let surface = SurfaceNode(anchor: anchor)
        surfaceNodes[anchor] = surface
        self.sceneView.scene.rootNode.addChildNode(surface)
    }
    func removeSurfaceNode(){
        // Remove all surfaces and tell session to forget about anchors
        surfaceNodes.forEach { (anchor, surfaceNode) in
            sceneView.session.remove(anchor: anchor)
            surfaceNode.removeFromParentNode()
        }
        surfaceNodes.removeAll()
    }
  

}











