import Foundation
import CocoaLumberjackSwift

class StorageController: NSObject {

    private var operationQueue: OperationQueue
    private var managedObjectContext: NSManagedObjectContext
    
    private let pruningAge: TimeInterval = 60*60*24*30 // 30 days

    init?(_ ignore: Bool = false) {
        let fileManager = FileManager.default
        let storageDirectory = fileManager.wmf_containerURL().appendingPathComponent("EventPlatformClient", isDirectory: true)
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            do {
                let storageDirectoryIsReachable = try storageDirectory.checkResourceIsReachable()
                if !storageDirectoryIsReachable {
                    DDLogError("Event Platform Client storage directory is unreachable")
                    return nil
                }
            } catch {
                DDLogError("Error when attempting to reach Event Platform Client storage directory")
                return nil
            }
        }

        let modelURL = Bundle.wmf.url(forResource: "EventPlatformClient", withExtension: "momd")!
        let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel(contentsOf: modelURL)!)
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator
        self.managedObjectContext = managedObjectContext
        
        operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
    }
    
    func push(stream: EPC.Stream, event: EPC.Event) {
        let now = NSDate()
        self.managedObjectContext.perform() {
            let record = NSEntityDescription.insertNewObject(forEntityName: "WMFEPCEventRecord", into: self.managedObjectContext) as! EPCEventRecord
            record.event = event
            record.recorded = now
            
            DDLogDebug("EPC StorageController: \(record.objectID) recorded!")
            
            guard self.managedObjectContext.hasChanges else {
                return
            }
            do {
                try self.managedObjectContext.save()
            } catch let error {
                DDLogError("Error saving EventLoggingService managedObjectContext: \(error)")
            }
        }
    }
    
    func popAll() -> [EventPlatformEvent] {
        var result: [EventPlatformEvent] = []
        self.managedObjectContext.perform() {
            let fetch: NSFetchRequest<EventPlatformEvent> = EventPlatformEvent.fetchRequest()
            fetch.sortDescriptors = [NSSortDescriptor(keyPath: \EventPlatformEvent.recorded, ascending: true)]
            fetch.predicate = NSPredicate(format: "(posted == nil) AND (failed != TRUE)")

            do {
                let fetchResult = try self.managedObjectContext.fetch(fetch)
                if (fetchResult.count > 0) {
                    result += fetchResult
                }
            } catch let error {
                DDLogError(error.localizedDescription)
            }
        }
        return result
    }
    
    private func pruneExpiredEvents(_ completion: (() -> Void)? = nil) {
        let operation = AsyncBlockOperation { (operation) in
            self.managedObjectContext.perform() {
                let pruneFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "WMFEventPlatformEvent")
                pruneFetch.returnsObjectsAsFaults = false
        
                let pruneDate = Date().addingTimeInterval(-(self.pruningAge)) as NSDate
                pruneFetch.predicate = NSPredicate(format: "(recorded < %@) OR (posted != nil) OR (failed == TRUE)", pruneDate)
        
                let delete = NSBatchDeleteRequest(fetchRequest: pruneFetch)
                delete.resultType = .resultTypeCount
            }
        }
        operationQueue.addOperation(operation)
        guard let completion = completion else {
            return
        }
        let completionBlockOp = BlockOperation(block: completion)
        completionBlockOp.addDependency(operation)
        operationQueue.addOperation(completion)
    }
}

extension StorageController: PeriodicWorker {
    public func doPeriodicWork(_ completion: @escaping () -> Void) {
        self.pruneExpiredEvents(completion)
    }
}
