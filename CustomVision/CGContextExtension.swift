//
//  CGContextExtension.swift
//  VirtualPyhsics
//
//  Created by Umut BOZ on 30.07.2018.
//  Copyright © 2018 Adam Behringer. All rights reserved.
//

import Foundation
import CoreGraphics
import Darwin
import UIKit
extension CGContext {
    func addRect(rect:CGRect, fillColor:UIColor, strokeColor:UIColor, width:CGFloat) {
        self.addRect(rect)
        self.fillAndStroke(fillColor: fillColor, strokeColor: strokeColor, width: width)
        
    }
    func fillAndStroke(fillColor:UIColor, strokeColor:UIColor, width:CGFloat) {
        self.setFillColor(fillColor.cgColor)
        self.setStrokeColor(strokeColor.cgColor)
        self.setLineWidth(width)
        self.drawPath(using: CGPathDrawingMode.fillStroke)
    }
    
}
