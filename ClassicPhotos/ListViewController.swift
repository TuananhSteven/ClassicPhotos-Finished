//
//  ViewController.swift
//  ClassicPhotos
//
//  Created by Tuan Anh Ngo on 6/23/17.
//  Copyright © 2017 TuanAnh. All rights reserved.
//

import UIKit
import CoreImage

let dataSourceURL = URL(string:"http://www.raywenderlich.com/downloads/ClassicPhotosDictionary.plist")

class ListViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    
    var photos = [PhotoRecord]()
    let pendingOperations = PendingOperations()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        tableView.dataSource = self
        tableView.delegate = self
        
        fetchPhotoDetails()
    }

    func fetchPhotoDetails() {
        let request = URLRequest(url:dataSourceURL!)
        UIApplication.shared.isNetworkActivityIndicatorVisible = true

        NSURLConnection.sendAsynchronousRequest(request, queue: OperationQueue.main) {response,data,error in
            if data != nil {
                let datasourceDictionary = try! PropertyListSerialization.propertyList(from:data!, options: [], format: nil) as! NSDictionary
                
                for (key,value) in datasourceDictionary.enumerated() {
                    let name = String(describing: value.key)
                    print("key : \(name) , value: \(value)")
                    let url = NSURL(string:value.value as? String ?? "")
                    if name != nil && url != nil {
                        let photoRecord = PhotoRecord(name:name, url:url!)
                        self.photos.append(photoRecord)
                    }
                }
                
                self.tableView.reloadData()
            }
            
            if error != nil {
                let alert = UIAlertView(title:"Oops!",message:error?.localizedDescription, delegate:nil, cancelButtonTitle:"OK")
                alert.show()
            }
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
        }
        
    }

}

extension ListViewController:UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return photos.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CellIdentifier", for: indexPath)
        
        //1
        if cell.accessoryView == nil {
            let indicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
            cell.accessoryView = indicator
        }
        let indicator = cell.accessoryView as! UIActivityIndicatorView
        
        //2
        let photoDetails = photos[indexPath.row]
        
        //3
        cell.textLabel?.text = photoDetails.name
        cell.imageView?.image = photoDetails.image
        
        //4
        switch (photoDetails.state){
        case .Filtered:
            indicator.stopAnimating()
        case .Failed:
            indicator.stopAnimating()
            cell.textLabel?.text = "Failed to load"
        case .New, .Downloaded:
            indicator.startAnimating()
            if (!tableView.isDragging && !tableView.isDecelerating) {
                self.startOperationsForPhotoRecord(photoDetails: photoDetails, indexPath: indexPath as NSIndexPath)
            }
        }
        
        return cell
    }
    
    func startOperationsForPhotoRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
        switch (photoDetails.state) {
        case .New:
            startDownloadForRecord(photoDetails: photoDetails, indexPath: indexPath)
        case .Downloaded:
            startFiltrationForRecord(photoDetails: photoDetails, indexPath: indexPath)
        default:
            NSLog("do nothing")
        }
    }
    
    func startDownloadForRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
        //1
        if pendingOperations.downloadsInProgress[indexPath] != nil {
            return
        }
        
        //2
        let downloader = ImageDownloader(photoRecord: photoDetails)
        //3
        downloader.completionBlock = {
            if downloader.isCancelled {
                return
            }
            DispatchQueue.main.async(execute: {
                self.pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
                self.tableView.reloadRows(at: [indexPath as IndexPath], with: .fade)
            })
        }
        //4
        pendingOperations.downloadsInProgress[indexPath] = downloader
        //5
        pendingOperations.downloadQueue.addOperation(downloader)
    }
    
    func startFiltrationForRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
        if pendingOperations.filtrationsInProgress[indexPath] != nil{
            return
        }
        
        let filterer = ImageFiltration(photoRecord: photoDetails)
        filterer.completionBlock = {
            if filterer.isCancelled {
                return
            }
            DispatchQueue.main.async(execute: {
                self.pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
                self.tableView.reloadRows(at: [indexPath as IndexPath], with: .fade)
            })
        }
        pendingOperations.filtrationsInProgress[indexPath] = filterer
        pendingOperations.filtrationQueue.addOperation(filterer)
    }
}

extension ListViewController:UIScrollViewDelegate, UITableViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        //1
        suspendAllOperations()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // 2
        if !decelerate {
            loadImagesForOnscreenCells()
            resumeAllOperations()
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // 3
        loadImagesForOnscreenCells()
        resumeAllOperations()
    }
    
    func suspendAllOperations () {
        pendingOperations.downloadQueue.isSuspended = true
        pendingOperations.filtrationQueue.isSuspended = true
    }
    
    func resumeAllOperations () {
        pendingOperations.downloadQueue.isSuspended = false
        pendingOperations.filtrationQueue.isSuspended = false
    }
    
    func loadImagesForOnscreenCells () {
        //1
        if let pathsArray = tableView.indexPathsForVisibleRows {
            //2y
            var allPendingOperations = Set(Array(pendingOperations.downloadsInProgress.keys))
            allPendingOperations.formUnion(Set(Array(pendingOperations.filtrationsInProgress.keys)))
            
            //3
            var toBeCancelled = allPendingOperations
            let visiblePaths = Set(pathsArray )
            toBeCancelled.subtract(visiblePaths as Set<NSIndexPath>)
            
            //4
            var toBeStarted = visiblePaths
            toBeStarted.subtract(allPendingOperations as Set<IndexPath>)
            
            // 5
            for indexPath in toBeCancelled {
                if let pendingDownload = pendingOperations.downloadsInProgress[indexPath] {
                    pendingDownload.cancel()
                }
                pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
                if let pendingFiltration = pendingOperations.filtrationsInProgress[indexPath] {
                    pendingFiltration.cancel()
                }
                pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
            }
            
            // 6
            for indexPath in toBeStarted {
                let indexPath = indexPath as NSIndexPath
                let recordToProcess = self.photos[indexPath.row]
                startOperationsForPhotoRecord(photoDetails: recordToProcess, indexPath: indexPath)
            }
        }
    }

}


