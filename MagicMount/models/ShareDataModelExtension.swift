//
//  ShareDataModelExtension.swift
//  MagicMount
//
//  Created by Mark Tassinari on 2/1/26.
//

import Foundation
import libMounter
extension ShareDataModel {
    var mainViewModel : MountsViewModel {
        return MountsViewModel(service: DefaultServiceInterface())
    }
}

