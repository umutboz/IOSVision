//
//  CustomVisionAI.swift
//  VirtualPyhsics
//
//  Created by Umut BOZ on 30.07.2018.
//  Copyright © 2018 Adam Behringer. All rights reserved.
//

import Foundation
import Alamofire
class CustomVisionAI {
    let headers : HTTPHeaders = HTTPHeaders()
    let url : String = "https://southcentralus.api.cognitive.microsoft.com/customvision/v2.0/Prediction/f767909e-1304-42da-b0a3-a20ba0f38f70/image?iterationId=3ec375b6-204c-49e7-8242-3b8ce08caf37"
    let headerData:[String : String] = ["Content-Type": "application/octet-stream" , "Prediction-Key":"3081acb7570044699c3d3b3e0a3c92dd"]
    init() {
        setTimeout(600000)
    }
    public func setTimeout(_ timeout: Int) -> Self {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = TimeInterval(timeout)
        configuration.timeoutIntervalForRequest = TimeInterval(timeout)
        return self
    }
    func upload(image : UIImage,completionSuccess: @escaping (_ result: [Prediction]) -> Void,completionError: @escaping (_ error: Error) -> Void) -> Void {
        //let imageData = UIImageJPEGRepresentation(image, 0.5)
        let data = UIImagePNGRepresentation(image)
        let uploadReq = Alamofire.upload(data!, to: url, method: HTTPMethod.post, headers: headerData)
        uploadReq.responseString{ response in
            switch response.result {
                case .success:
                    let statusCode = response.response?.statusCode
                    print(statusCode)
                    do{
                        var errorTemp = NSError(domain:"", code:statusCode!, userInfo:nil)
                        var responseDictionary = self.getMappedModel(json: response.result.value!)
                        let predictionsArray = responseDictionary?["predictions"] as? NSArray
                        let jsonData = try JSONSerialization.data(withJSONObject: predictionsArray, options: JSONSerialization.WritingOptions.prettyPrinted)
                        if let JSONString = String(data: jsonData, encoding: String.Encoding.utf8) {
                            print(JSONString)
                            let predictions = try JSONDecoder().decode([Prediction].self, from:(JSONString.data(using: .utf8))!)
                            print("JSONString")
                            if predictions.count > 0 {
                                let pred = predictions.sorted(by: { $0.probability! > $1.probability! })
                               completionSuccess(pred)
                            } else {
                            
                                completionError(errorTemp)
                            }
                        }
                        else{
                            print("error")
                            completionError(errorTemp)
                        }
                        
                    }
                    catch{
                         completionError(error)
                    }
                
                case .failure(let error):
                    completionError(error)
                }
            }
        }
    
     func getMappedModel(json: String) -> [String: Any]? {
        let dictionary = try? JSONSerializer.toDictionary(json)
        return dictionary as? [String: Any]
    }
}
public class VisionAIModel: Codable {
    
    let id : String?
    let project : String?
    let iteration : String?
    let created : String?
    let predictions : [Prediction]? = []
    
    init(id : String, project : String, iteration : String, created : String) {
        self.id = id
        self.project = project
        self.iteration = iteration
        self.created = created
    }
}
public class RequestModel{
    let Url : String?
    init(Url : String){
        self.Url = Url
    }
}
public class Prediction : Codable{
    
    let probability : Double?
    let tagName : String?
    let tagId : String?
    let boundingBox : BoundingBox?
    
    init(probability : Double, tagName : String, tagId : String,boundingBox : BoundingBox) {
        self.probability = probability
        self.tagName = tagName
        self.tagId = tagId
        self.boundingBox = boundingBox
    }
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: PredictionCodingKeys.self)
        try container.encode (probability, forKey: .probability)
        try container.encode (tagName, forKey: .tagName)
        try container.encode (tagId, forKey: .tagId)
        try container.encode (boundingBox, forKey: .boundingBox)
    }
    
    enum PredictionCodingKeys: String, CodingKey {
        case probability  = "probability"
        case tagName = "tagName"
        case tagId = "tagId"
        case boundingBox = "boundingBox"
    }
}
public class BoundingBox : Codable{
    let left : Double?
    let top : Double?
    let width : Double?
    let height : Double?
    
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: BoundingBoxCodingKeys.self)
        try container.encode (left, forKey: .left)
        try container.encode (top, forKey: .top)
        try container.encode (width, forKey: .width)
        try container.encode (height, forKey: .height)
    }
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BoundingBoxCodingKeys.self)
        left = (try container.decodeIfPresent(Double.self, forKey: .left))
        top = (try container.decodeIfPresent(Double.self, forKey: .top))
        width = (try container.decodeIfPresent(Double.self, forKey: .width))
        height = (try container.decodeIfPresent(Double.self, forKey: .height))
    }
    enum BoundingBoxCodingKeys: String, CodingKey {
        case left  = "left"
        case top = "top"
        case width = "width"
        case height = "height"
    }
}
