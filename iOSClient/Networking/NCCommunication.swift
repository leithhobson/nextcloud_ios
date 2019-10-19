//
//  NCCommunication.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 12/10/19.
//  Copyright © 2018 Marino Faggiana. All rights reserved.
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
import Alamofire
import SwiftyXMLParser

class NCCommunication: SessionDelegate {
    @objc static let sharedInstance: NCCommunication = {
        let instance = NCCommunication()
        return instance
    }()
    
    var username = ""
    var password = ""
    var userAgent: String?
    var directoryCertificate: String = ""
    
    // Session Manager
    
    private lazy var sessionManagerData: Alamofire.Session = {
        let configuration = URLSessionConfiguration.af.default
        return Alamofire.Session(configuration: configuration, eventMonitors: self.makeEvents())
    }()
   
    private lazy var sessionManagerTransfer: Alamofire.Session = {
        let configuration = URLSessionConfiguration.af.default
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 5
        return Alamofire.Session(configuration: configuration, eventMonitors: self.makeEvents())
    }()
    
    private lazy var sessionManagerTransferWWan: Alamofire.Session = {
        let configuration = URLSessionConfiguration.af.default
        configuration.allowsCellularAccess = false
        configuration.httpMaximumConnectionsPerHost = 5
        return Alamofire.Session(configuration: configuration, eventMonitors: self.makeEvents())
    }()
    
    //MARK: - Settings

    @objc func settingAccount(username: String, password: String) {
        self.username = username
        self.password = password
    }
    
    @objc func settingUserAgent(_ userAgent: String) {
        self.userAgent = userAgent
    }
    
    //MARK: - monitor
    
    private func makeEvents() -> [EventMonitor] {
        let events = ClosureEventMonitor()
        events.requestDidFinish = { request in
            print("Request finished \(request)")
        }
        events.taskDidComplete = { session, task, error in
            print("Request failed \(session) \(task) \(String(describing: error))")
            /*
            if  let urlString = (error as NSError?)?.userInfo["NSErrorFailingURLStringKey"] as? String,
                let resumedata = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                print("Found resume data for url \(urlString)")
                //self.startDownload(urlString, resumeData: resumedata)
            }
            */
        }
        return [events]
    }
    
    //MARK: - webDAV

    @objc func createFolder(_ serverUrlFileName: String, completionHandler: @escaping (_ ocId: String?, _ date: NSDate?, _ error: Error?) -> Void) {
        
        // url
        guard let url = NCCommunicationCommon.sharedInstance.encodeUrlString(serverUrlFileName) else {
            completionHandler(nil, nil, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
            return
        }
        
        // method
        let method = HTTPMethod(rawValue: "MKCOL")
        
        // headers
        var headers: HTTPHeaders = [.authorization(username: self.username, password: self.password)]
        if let userAgent = self.userAgent { headers.update(.userAgent(userAgent)) }
        
        sessionManagerData.request(url, method: method, parameters:nil, encoding: URLEncoding.default, headers: headers, interceptor: nil).validate(statusCode: 200..<300).response { (response) in
            switch response.result {
            case.failure(let error):
                completionHandler(nil, nil, error)
            case .success( _):
                let ocId = response.response?.allHeaderFields["OC-FileId"] as! String?
                if let dateString = response.response?.allHeaderFields["Date"] as! String? {
                    if let date = NCCommunicationCommon.sharedInstance.convertDate(dateString, format: "EEE, dd MMM y HH:mm:ss zzz") {
                        completionHandler(ocId, date, nil)
                    } else { completionHandler(nil, nil, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadServerResponse, userInfo: nil)) }
                } else { completionHandler(nil, nil, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadServerResponse, userInfo: nil)) }
            }
        }
    }
    
    @objc func deleteFileOrFolder(_ serverUrlFileName: String, completionHandler: @escaping (_ error: Error?) -> Void) {
        
        // url
        guard let url = NCCommunicationCommon.sharedInstance.encodeUrlString(serverUrlFileName) else {
            completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
            return
        }
        
        // method
        let method = HTTPMethod(rawValue: "DELETE")
        
        // headers
        var headers: HTTPHeaders = [.authorization(username: self.username, password: self.password)]
        if let userAgent = self.userAgent { headers.update(.userAgent(userAgent)) }
        
        sessionManagerData.request(url, method: method, parameters:nil, encoding: URLEncoding.default, headers: headers, interceptor: nil).validate(statusCode: 200..<300).response { (response) in
            switch response.result {
            case.failure(let error):
                completionHandler(error)
            case .success( _):
                completionHandler(nil)
            }
        }
    }
    
    @objc func moveFileOrFolder(serverUrlFileNameSource: String, serverUrlFileNameDestination: String, completionHandler: @escaping (_ error: Error?) -> Void) {
        
        // url
        guard let url = NCCommunicationCommon.sharedInstance.encodeUrlString(serverUrlFileNameSource) else {
            completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
            return
        }
        
        // method
        let method = HTTPMethod(rawValue: "MOVE")
        
        // headers
        var headers: HTTPHeaders = [.authorization(username: self.username, password: self.password)]
        if let userAgent = self.userAgent { headers.update(.userAgent(userAgent)) }
        headers.update(name: "Destination", value: serverUrlFileNameDestination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        headers.update(name: "Overwrite", value: "T")
        
        sessionManagerData.request(url, method: method, parameters:nil, encoding: URLEncoding.default, headers: headers, interceptor: nil).validate(statusCode: 200..<300).response { (response) in
            switch response.result {
            case.failure(let error):
                completionHandler(error)
            case .success( _):
                completionHandler(nil)
            }
        }
    }
    
    @objc func readFileOrFolder(serverUrlFileName: String, depth: String, completionHandler: @escaping (_ result: [NCFile], _ error: Error?) -> Void) {
        
        var files = [NCFile]()
        var isNotFirstFileOfList: Bool = false
        let dataFile =
        """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <d:propfind xmlns:d=\"DAV:\" xmlns:oc=\"http://owncloud.org/ns\" xmlns:nc=\"http://nextcloud.org/ns\">
        <d:prop>

        <d:getlastmodified />
        <d:getetag />
        <d:getcontenttype />
        <d:resourcetype />
        <d:quota-available-bytes />
        <d:quota-used-bytes />

        <permissions xmlns=\"http://owncloud.org/ns\"/>
        <id xmlns=\"http://owncloud.org/ns\"/>
        <fileid xmlns=\"http://owncloud.org/ns\"/>
        <size xmlns=\"http://owncloud.org/ns\"/>
        <favorite xmlns=\"http://owncloud.org/ns\"/>
        <share-types xmlns=\"http://owncloud.org/ns\"/>
        <owner-id xmlns=\"http://owncloud.org/ns\"/>
        <owner-display-name xmlns=\"http://owncloud.org/ns\"/>
        <comments-unread xmlns=\"http://owncloud.org/ns\"/>

        <is-encrypted xmlns=\"http://nextcloud.org/ns\"/>
        <has-preview xmlns=\"http://nextcloud.org/ns\"/>
        <mount-type xmlns=\"http://nextcloud.org/ns\"/>

        </d:prop>
        </d:propfind>
        """

        // url
        var serverUrlFileName = String(serverUrlFileName)
        if depth == "1" && serverUrlFileName.last != "/" { serverUrlFileName = serverUrlFileName + "/" }
        if depth == "0" && serverUrlFileName.last == "/" { serverUrlFileName = String(serverUrlFileName.remove(at: serverUrlFileName.index(before: serverUrlFileName.endIndex))) }
        guard let url = NCCommunicationCommon.sharedInstance.encodeUrlString(serverUrlFileName) else {
            completionHandler(files, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
            return
        }
        
        // method
        let method = HTTPMethod(rawValue: "PROPFIND")
        
        // headers
        var headers: HTTPHeaders = [.authorization(username: self.username, password: self.password)]
        if let userAgent = self.userAgent { headers.update(.userAgent(userAgent)) }
        headers.update(.contentType("application/xml"))
        headers.update(name: "Depth", value: depth)

        // request
        var urlRequest: URLRequest
        do {
            try urlRequest = URLRequest(url: url, method: method, headers: headers)
            urlRequest.httpBody = dataFile.data(using: .utf8)
        } catch let error {
            completionHandler(files, error)
            return
        }
        
        sessionManagerData.request(urlRequest).validate(statusCode: 200..<300).responseData { (response) in
            switch response.result {
            case.failure(let error):
                completionHandler(files, error)
            case .success( _):
                if let data = response.data {
                    let xml = XML.parse(data)
                    let elements = xml["d:multistatus", "d:response"]
                    for element in elements {
                        let file = NCFile()
                        if let href = element["d:href"].text {
                            var fileNamePath = href
                            // directory
                            if href.last == "/" {
                                fileNamePath = String(href[..<href.index(before: href.endIndex)])
                                file.directory = true
                            }
                            // path
                            file.path = (fileNamePath as NSString).deletingLastPathComponent + "/"
                            file.path = file.path.removingPercentEncoding ?? ""
                            // fileName
                            if isNotFirstFileOfList {
                                file.fileName = (fileNamePath as NSString).lastPathComponent
                                file.fileName = file.fileName.removingPercentEncoding ?? ""
                            } else {
                                file.fileName = ""
                            }
                        }
                        let propstat = element["d:propstat"][0]
                        
                        // d:
                        
                        if let getlastmodified = propstat["d:prop", "d:getlastmodified"].text {
                            if let date = NCCommunicationCommon.sharedInstance.convertDate(getlastmodified, format: "EEE, dd MMM y HH:mm:ss zzz") {
                                file.date = date
                            }
                        }
                        if let getetag = propstat["d:prop", "d:getetag"].text {
                            file.etag = getetag.replacingOccurrences(of: "\"", with: "")
                        }
                        if let getcontenttype = propstat["d:prop", "d:getcontenttype"].text {
                            file.contentType = getcontenttype
                        }
                        if let resourcetype = propstat["d:prop", "d:resourcetype"].text {
                            file.resourceType = resourcetype
                        }
                        if let quotaavailablebytes = propstat["d:prop", "d:quota-available-bytes"].text {
                            file.quotaAvailableBytes = Double(quotaavailablebytes) ?? 0
                        }
                        if let quotausedbytes = propstat["d:prop", "d:quota-used-bytes"].text {
                            file.quotaUsedBytes = Double(quotausedbytes) ?? 0
                        }
                        
                        // oc:
                       
                        if let permissions = propstat["d:prop", "oc:permissions"].text {
                            file.permissions = permissions
                        }
                        if let ocId = propstat["d:prop", "oc:id"].text {
                            file.ocId = ocId
                        }
                        if let fileId = propstat["d:prop", "oc:fileid"].text {
                            file.fileId = fileId
                        }
                        if let size = propstat["d:prop", "oc:size"].text {
                            file.size = Double(size) ?? 0
                        }
                        if let favorite = propstat["d:prop", "oc:favorite"].text {
                            file.favorite = (favorite as NSString).boolValue
                        }
                        if let ownerid = propstat["d:prop", "oc:owner-id"].text {
                            file.ownerId = ownerid
                        }
                        if let ownerdisplayname = propstat["d:prop", "oc:owner-display-name"].text {
                            file.ownerDisplayName = ownerdisplayname
                        }
                        if let commentsunread = propstat["d:prop", "oc:comments-unread"].text {
                            file.commentsUnread = (commentsunread as NSString).boolValue
                        }
                        
                        // nc:
                        if let encrypted = propstat["d:prop", "nc:encrypted"].text {
                            file.e2eEncrypted = (encrypted as NSString).boolValue
                        }
                        if let haspreview = propstat["d:prop", "nc:has-preview"].text {
                            file.hasPreview = (haspreview as NSString).boolValue
                        }
                        if let mounttype = propstat["d:prop", "nc:mount-type"].text {
                            file.mountType = mounttype
                        }
                        
                        isNotFirstFileOfList = true;
                        files.append(file)
                    }
                    completionHandler(files, nil)
                } else {
                    completionHandler(files, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadServerResponse, userInfo: nil))
                }
            }
        }
    }
    
    @objc func setFavorite(urlString: String, fileName: String, favorite: Bool, completionHandler: @escaping (_ error: Error?) -> Void) {
        
        let dataFile =
        """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <d:propfind xmlns:d=\"DAV:\" xmlns:oc=\"http://owncloud.org/ns\" xmlns:nc=\"http://nextcloud.org/ns\">
        <d:set>
        <d:prop>
        <oc:favorite>%i</oc:favorite>
        </d:prop>
        </d:set>
        </d:propertyupdate>
        """
        let body = NSString.init(format: dataFile as NSString, (favorite ? 1 : 0)) as String
        
        // url
        let serverUrlFileName = urlString + "/remote.php/dav/files/" + username + "/" + fileName
 
        guard let url = NCCommunicationCommon.sharedInstance.encodeUrlString(serverUrlFileName) else {
            completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
            return
        }
        
        // method
        let method = HTTPMethod(rawValue: "PROPPATCH")
        
        // headers
        var headers: HTTPHeaders = [.authorization(username: self.username, password: self.password)]
        if let userAgent = self.userAgent { headers.update(.userAgent(userAgent)) }
        headers.update(.contentType("application/xml"))
        
        // request
        var urlRequest: URLRequest
        do {
            try urlRequest = URLRequest(url: url, method: method, headers: headers)
            urlRequest.httpBody = body.data(using: .utf8)
        } catch let error {
            completionHandler(error)
            return
        }
        
        sessionManagerData.request(urlRequest).validate(statusCode: 200..<300).responseData { (response) in
            switch response.result {
            case.failure(let error):
                completionHandler(error)
            case .success( _):
                completionHandler(nil)
            }
        }
    }
    
    //MARK: - API
    @objc func downloadPreview(serverUrl: String, fileNamePath: String, fileNamePathLocalDestination: String, width: CGFloat, height: CGFloat, completionHandler: @escaping (_ data: Data?, _ error: Error?) -> Void) {
        
        // url
        var serverUrl = String(serverUrl)
        if serverUrl.last != "/" { serverUrl = serverUrl + "/" }
        serverUrl = serverUrl + "index.php/core/preview.png?file=" + fileNamePath + "&x=\(width)&y=\(height)&a=1&mode=cover"
        guard let url = NCCommunicationCommon.sharedInstance.encodeUrlString(serverUrl) else {
            completionHandler(nil, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
            return
        }
        
        // method
        let method = HTTPMethod(rawValue: "GET")
        
        // headers
        var headers: HTTPHeaders = [.authorization(username: self.username, password: self.password)]
        if let userAgent = self.userAgent { headers.update(.userAgent(userAgent)) }

        sessionManagerData.request(url, method: method, parameters:nil, encoding: URLEncoding.default, headers: headers, interceptor: nil).validate(statusCode: 200..<300).response { (response) in
            switch response.result {
            case.failure(let error):
                completionHandler(nil, error)
            case .success( _):
                if let data = response.data {
                    do {
                        let url = URL.init(fileURLWithPath: fileNamePathLocalDestination)
                        try  data.write(to: url, options: .atomic)
                        completionHandler(data, nil)
                    } catch let error {
                        completionHandler(nil, error)
                    }
                } else {
                    completionHandler(nil, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorCannotDecodeContentData, userInfo: nil))
                }
            }
        }
    }
    
    //MARK: - File transfer
    
    @objc func download(serverUrlFileName: String, fileNamePathLocalDestination: String, progressHandler: @escaping (_ progress: Progress) -> Void , completionHandler: @escaping (_ etag: String?, _ date: NSDate?, _ lenght: Double, _ error: Error?) -> Void) -> URLSessionTask? {
        
        let sessionManager: Alamofire.Session
        sessionManager = sessionManagerTransfer
        sessionManager.session.sessionDescription = NCCommunicationCommon.sharedInstance.download_session
        
        // url
        guard let url = NCCommunicationCommon.sharedInstance.encodeUrlString(serverUrlFileName) else {
            completionHandler(nil, nil, 0, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
            return nil
        }
        
        // destination
        var destination: Alamofire.DownloadRequest.Destination?
        if let fileNamePathLocalDestinationURL = URL(string: fileNamePathLocalDestination) {
            let destinationFile: DownloadRequest.Destination = { _, _ in
                return (fileNamePathLocalDestinationURL, [.removePreviousFile, .createIntermediateDirectories])
            }
            destination = destinationFile
        }
        
        // headers
        var headers: HTTPHeaders = [.authorization(username: self.username, password: self.password)]
        if let userAgent = self.userAgent { headers.update(.userAgent(userAgent)) }
        
        let request = sessionManager.download(url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: headers, interceptor: nil, to: destination)
        .downloadProgress { progress in
            progressHandler(progress)
        }
        .validate(statusCode: 200..<300)
        .response { response in
            switch response.result {
            case.failure(let error):
                completionHandler(nil, nil, 0, error)
            case .success( _):
                let lenght = response.response?.allHeaderFields["lenght"] as! Double
                var etag = response.response?.allHeaderFields["OC-ETag"] as! String?
                if etag != nil { etag = etag!.replacingOccurrences(of: "\"", with: "") }
                if let dateString = response.response?.allHeaderFields["Date"] as! String? {
                    if let date = NCCommunicationCommon.sharedInstance.convertDate(dateString, format: "EEE, dd MMM y HH:mm:ss zzz") {
                        completionHandler(etag, date, lenght, nil)
                    } else { completionHandler(nil, nil, 0, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadServerResponse, userInfo: nil)) }
                } else { completionHandler(nil, nil, 0, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadServerResponse, userInfo: nil)) }
            }
        }
        
        return request.task
    }
    
    @objc func upload(serverUrlFileName: String, fileNamePathSource: String, progressHandler: @escaping (_ progress: Progress) -> Void ,completionHandler: @escaping (_ ocId: String?, _ etag: String?, _ date: NSDate?, _ error: Error?) -> Void) -> URLSessionTask? {
        
        let sessionManager: Alamofire.Session
        sessionManager = sessionManagerTransfer
        sessionManager.session.sessionDescription = NCCommunicationCommon.sharedInstance.upload_session
        
        // url
        guard let url = NCCommunicationCommon.sharedInstance.encodeUrlString(serverUrlFileName) else {
            completionHandler(nil, nil, nil, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
            return nil
        }
        let fileNamePathSourceUrl = URL.init(fileURLWithPath: fileNamePathSource)
        
        // headers
        var headers: HTTPHeaders = [.authorization(username: self.username, password: self.password)]
        if let userAgent = self.userAgent { headers.update(.userAgent(userAgent)) }
        
        let request = sessionManager.upload(fileNamePathSourceUrl, to: url, method: .put, headers: headers, interceptor: nil, fileManager: .default)
        .uploadProgress { progress in
            progressHandler(progress)
        }
        .validate(statusCode: 200..<300)
        .response { response in
            switch response.result {
            case.failure(let error):
                completionHandler(nil, nil, nil, error)
            case .success( _):
                let ocId = response.response?.allHeaderFields["OC-FileId"] as! String?
                var etag = response.response?.allHeaderFields["OC-ETag"] as! String?
                if etag != nil { etag = etag!.replacingOccurrences(of: "\"", with: "") }
                if let dateString = response.response?.allHeaderFields["Date"] as! String? {
                    if let date = NCCommunicationCommon.sharedInstance.convertDate(dateString, format: "EEE, dd MMM y HH:mm:ss zzz") {
                        completionHandler(ocId, etag, date, nil)
                    } else { completionHandler(nil, nil, nil, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadServerResponse, userInfo: nil)) }
                } else { completionHandler(nil, nil, nil, NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadServerResponse, userInfo: nil)) }
            }
        }
        
        return request.task
    }
    
    //MARK: - SessionDelegate

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if NCCommunicationCertificate.sharedInstance.checkTrustedChallenge(challenge: challenge, directoryCertificate: directoryCertificate) {
             completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, URLCredential.init(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
        }
    }
}

