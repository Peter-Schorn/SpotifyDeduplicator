//
//  CDPlaylist+CoreDataProperties.swift
//  SpotifyDeduplicator
//
//  Created by Peter Schorn on 9/10/20.
//  Copyright © 2020 Peter Schorn. All rights reserved.
//
//

import Foundation
import CoreData


extension CDPlaylist {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPlaylist> {
        return NSFetchRequest<CDPlaylist>(entityName: "CDPlaylist")
    }

    @NSManaged public var imageData: Data?
    @NSManaged public var index: Int64
    @NSManaged public var lastImageRequestedSnapshotId: String?
    @NSManaged public var lastTrackCheckedSnapshotId: String?
    @NSManaged public var name: String?
    @NSManaged public var snapshotId: String?
    @NSManaged public var tracksCount: Int64
    @NSManaged public var uri: String?
    @NSManaged public var albums: NSSet?
    @NSManaged public var duplicatesCount: Int64

}

// MARK: Generated accessors for albums
extension CDPlaylist {

    @objc(addAlbumsObject:)
    @NSManaged public func addToAlbums(_ value: CDAlbum)

    @objc(removeAlbumsObject:)
    @NSManaged public func removeFromAlbums(_ value: CDAlbum)

    @objc(addAlbums:)
    @NSManaged public func addToAlbums(_ values: NSSet)

    @objc(removeAlbums:)
    @NSManaged public func removeFromAlbums(_ values: NSSet)

}
