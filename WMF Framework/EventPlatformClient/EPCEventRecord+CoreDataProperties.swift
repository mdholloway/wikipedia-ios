import Foundation
import CoreData

extension EPCEventRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<EPCEventRecord> {
        return NSFetchRequest<EPCEventRecord>(entityName: "WMFEPCEventRecord")
    }

    @NSManaged public var event: NSObject
    @NSManaged public var recorded: NSDate?
    @NSManaged public var posted: NSDate?
    @NSManaged public var postAttempts: Int16
    @NSManaged public var failed: Bool

}
