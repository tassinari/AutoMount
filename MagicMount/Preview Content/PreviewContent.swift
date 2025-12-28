//
//  PreviewContent.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//
import Foundation

class PreviewData {
    static let mockShares: [Volume] = [
        Volume(name: "Media",
               url: URL(string:"smb://nas.local/Media")!,
               uuid: UUID().uuidString,
               local: false,
               mountPoint: "/Volumes/Media"
              ),
        Volume(name: "Projects",
               url: URL( string:"smb://fileserver/Projects")!,
               uuid: UUID().uuidString,
               local: false,
               mountPoint: "/Volumes/Projects"
              ),
        Volume(name: "Backup",
               url: URL( string:"nfs://backup.local:/exports/backup")!,
               uuid: UUID().uuidString,
               local: false,
               mountPoint: "/Volumes/Backup"
              ),
        Volume(name: "USB Drive",
               url: URL( string:"file:///Volumes/USB%20Drive")!,
               uuid: UUID().uuidString,
               local: false,
               mountPoint: "/Volumes/USB Drive"
              )
    ]

}
