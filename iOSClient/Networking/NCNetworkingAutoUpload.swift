//
//  NCNetworkingAutoUpload.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 25/06/2020.
//  Copyright © 2020 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import NCCommunication

class NCNetworkingAutoUpload: NSObject {

    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    var timerProcess: Timer?
    
    override init() {
        super.init()
        startTimer()
    }
    
    @objc func startProcess() {
        if timerProcess?.isValid ?? false {
            process()
        }
    }
    
    func startTimer() {
        timerProcess = Timer.scheduledTimer(timeInterval: TimeInterval(k_timerAutoUpload), target: self, selector: #selector(process), userInfo: nil, repeats: true)
    }

    @objc private func process() {

        var counterUpload: Int = 0
        var sizeUpload = 0
        var maxConcurrentOperationUpload = Int(k_maxConcurrentOperation)
        
        if appDelegate.account == nil || appDelegate.account.count == 0 || appDelegate.maintenanceMode {
            return
        }
        
        let metadatasUpload = NCManageDatabase.sharedInstance.getMetadatas(predicate: NSPredicate(format: "status == %d OR status == %d", k_metadataStatusInUpload, k_metadataStatusUploading))
        counterUpload = metadatasUpload.count
        for metadata in metadatasUpload {
            sizeUpload = sizeUpload + Int(metadata.size)
        }
        if sizeUpload > k_maxSizeOperationUpload {
            return
        }
        
        timerProcess?.invalidate()
        
        debugPrint("[LOG] PROCESS-AUTO-UPLOAD \(counterUpload)")
    
        let sessionSelectors = [selectorUploadFile, selectorUploadAutoUpload, selectorUploadAutoUploadAll]
        for sessionSelector in sessionSelectors {
            if counterUpload < maxConcurrentOperationUpload {
                let limit = maxConcurrentOperationUpload - counterUpload
                var predicate = NSPredicate()
                if UIApplication.shared.applicationState == .background {
                    predicate = NSPredicate(format: "sessionSelector == %@ AND status == %d AND typeFile != %@", sessionSelector, k_metadataStatusWaitUpload, k_metadataTypeFile_video)
                } else {
                    predicate = NSPredicate(format: "sessionSelector == %@ AND status == %d", sessionSelector, k_metadataStatusWaitUpload)
                }
                let metadatas = NCManageDatabase.sharedInstance.getMetadatas(predicate: predicate, page: 1, limit: limit, sorted: "date", ascending: true)
                for metadata in metadatas {
                    if CCUtility.isFolderEncrypted(metadata.serverUrl, e2eEncrypted: metadata.e2eEncrypted, account: metadata.account, urlBase: metadata.urlBase) {
                        if UIApplication.shared.applicationState == .background { break }
                        maxConcurrentOperationUpload = 1
                        counterUpload += 1
                        if let metadata = NCManageDatabase.sharedInstance.setMetadataStatus(ocId: metadata.ocId, status: Int(k_metadataStatusInUpload)) {
                            NCNetworking.shared.upload(metadata: metadata, background: true) { (_, _) in }
                        }
                        startTimer()
                        return
                    } else {
                        counterUpload += 1
                        if let metadata = NCManageDatabase.sharedInstance.setMetadataStatus(ocId: metadata.ocId, status: Int(k_metadataStatusInUpload)) {
                            NCNetworking.shared.upload(metadata: metadata, background: true) { (_, _) in }
                        }
                        sizeUpload = sizeUpload + Int(metadata.size)
                        if sizeUpload > k_maxSizeOperationUpload {
                            startTimer()
                            return
                        }
                    }
                }
            } else {
                startTimer()
                return
            }
        }
        
        // No upload available ? --> Retry Upload in Error
        if counterUpload == 0 {
            let metadatas = NCManageDatabase.sharedInstance.getMetadatas(predicate: NSPredicate(format: "status == %d", k_metadataStatusUploadError))
            for metadata in metadatas {
                NCManageDatabase.sharedInstance.setMetadataSession(ocId: metadata.ocId, session: NCCommunicationCommon.shared.sessionIdentifierBackground, sessionError: "", sessionTaskIdentifier: 0 ,status: Int(k_metadataStatusWaitUpload))
            }
        }
         
        // verify delete Asset Local Identifiers in auto upload (DELETE Photos album)
        if (counterUpload == 0 && appDelegate.passcodeViewController == nil) {
            NCUtility.shared.deleteAssetLocalIdentifiers(account: appDelegate.account, sessionSelector: selectorUploadAutoUpload) {
                self.startTimer()
            }
        } else {
            startTimer()
        }
     }
}

