//
//  CDPlaylist+CoreDataProperties.swift
//  SpotifyDeduplicator
//
//  Created by Peter Schorn on 9/7/20.
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
    @NSManaged public var lastTrackCheckedSnapshotId: String?
    @NSManaged public var name: String?
    @NSManaged public var snapshotId: String?
    @NSManaged public var uri: String?
    @NSManaged public var lastImageRequestedSnapshotId: String?
    @NSManaged public var tracksCount: Int64
    @NSManaged public var tracks: NSSet?

}

// MARK: Generated accessors for tracks
extension CDPlaylist {

    @objc(addTracksObject:)
    @NSManaged public func addToTracks(_ value: CDTrack)

    @objc(removeTracksObject:)
    @NSManaged public func removeFromTracks(_ value: CDTrack)

    @objc(addTracks:)
    @NSManaged public func addToTracks(_ values: NSSet)

    @objc(removeTracks:)
    @NSManaged public func removeFromTracks(_ values: NSSet)

}
