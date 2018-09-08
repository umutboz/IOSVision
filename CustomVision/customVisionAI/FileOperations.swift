//
//  FileOperations.swift
//  CustomVision
//
//  Created by Umut BOZ on 30.07.2018.
//  Copyright © 2018 Adam Behringer. All rights reserved.
//

import Foundation
import UIKit
class FileOperations{
    static func saveFile(image: UIImage)-> Void{
            if let data = UIImagePNGRepresentation(image) {
                let name = "cup-\(arc4random()).png"
                let filename = getDocumentsDirectory().appendingPathComponent(name)
                try? data.write(to: filename)
            }
    }
    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
