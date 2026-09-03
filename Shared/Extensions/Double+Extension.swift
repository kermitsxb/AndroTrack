//
//  Double+Extension.swift
//  ThermoTrack
//
//  Created by Benoit Sida on 2021-07-13.
//

import Foundation
import SwiftUI

extension Double {
    func toRadians() -> Double {
        return self * Double.pi / 180
    }
    func toCGFloat() -> CGFloat {
        return CGFloat(self)
    }
}
