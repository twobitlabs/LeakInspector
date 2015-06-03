@objc protocol LeakInspectorDelegate {
    func didLeakReference(ref: AnyObject, name: String)
}


@objc class LeakInspector {

    private class RefWatch {
        weak var ref: AnyObject?
        var name: String
        var date = NSDate()

        init(ref: AnyObject, name: String) {
            self.ref = ref
            self.name = name
        }
    }

    weak var delegate: LeakInspectorDelegate?
    private static let sharedInstance = LeakInspector()
    private var refsToWatch = [RefWatch]()
    private let simulator = TARGET_IPHONE_SIMULATOR == 1

    init() {
        if (simulator) {
            scheduleToRun()
        }
    }

    class func watchRef(ref: AnyObject) {
        if (sharedInstance.simulator) {
            watchRef(ref, name: _stdlib_getDemangledTypeName(ref))
        }
    }

    class func watchRef(ref: AnyObject, name: String) {
        if (sharedInstance.simulator) {
            var newRefToWatch = RefWatch(ref: ref, name: name)
            sharedInstance.refsToWatch.append(newRefToWatch)
        }
    }

    private func scheduleToRun() {
        let frequency = Int64(5 * Double(NSEC_PER_SEC))
        let delayTime = dispatch_time(DISPATCH_TIME_NOW, frequency)
        dispatch_after(delayTime, dispatch_get_main_queue()) { [weak self] in
            self?.checkForLeaks()
            self?.scheduleToRun()
        }
    }

    private func checkForLeaks() {
        var removeIndexes = [Int]()
        for (index, refWatch) in enumerate(refsToWatch) {
            if let ref: AnyObject = refWatch.ref {
                if (hasRefLikelyLeaked(refWatch)) {
                    alertThatRefHasLeaked(ref, name: refWatch.name)
                }
            } else {
                removeIndexes.append(index)
            }
        }

        for index in removeIndexes {
            refsToWatch.removeAtIndex(index)
        }
    }

    private func hasRefLikelyLeaked(refWatch: RefWatch) -> Bool {
        var hasRefLikelyLeaked = false
        if (abs(refWatch.date.timeIntervalSinceNow) > 5) {
            if let controller = refWatch.ref as? UIViewController {
                if (controller.parentViewController == nil && controller.navigationController == nil) {
                    hasRefLikelyLeaked = true;
                } else {
                    refWatch.date = NSDate()
                }
            } else {
                hasRefLikelyLeaked = true
            }
        }
        return hasRefLikelyLeaked;
    }

    private func alertThatRefHasLeaked(ref: AnyObject, name: String) {
        NSLog("Leak detected %@", name)
        if let delegate = delegate {
            delegate.didLeakReference(ref, name: name)
        }
    }
}