//
//  CDAlbum+CoreDataClass.swift
//  SpotifyDeduplicator
//
//  Created by Peter Schorn on 9/7/20.
//  Copyright © 2020 Peter Schorn. All rights reserved.
//
//

import Foundation
import CoreData
import SwiftUI
import SpotifyWebAPI

@objc(CDAlbum)
public class CDAlbum: NSManagedObject {

    /// Sets `name`, `uri`, and `imageURL`.
    func setFromAlbum(_ album: Album) {
        self.name = album.name
        self.uri = album.uri
        self.imageURL = album.images?.largest?.url
        
    }

}
