//
//  PreviewContent.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//
import Foundation

class PreviewData {
    static let mockShares: [Share] = [
        Share(user: "",
              password: "",
              url: URL(string:"smb://nas.local/Media")!,
              name: "Media",
              mountPoint: "/Volumes/Media",
              connected: false
             ),
        Share(user: "",
              password: "",
              url: URL( string:"smb://fileserver/Projects")!,
              name: "Projects",
              mountPoint: "/Volumes/Projects",
              connected: true
             ),
        Share(user: "",
              password: "",
              url: URL( string:"nfs://fileserver/Backup")!,
              name: "Projects",
              mountPoint: "/Volumes/Backup",
              connected: false
             ),
        Share(user: "",
              password: "",
              url: URL( string:"nfs://fileserver/USB%20Drive")!,
              name: "USB",
              mountPoint: "/Volumes/USB Drive",
              connected: true
             ),
       
    ]

}
