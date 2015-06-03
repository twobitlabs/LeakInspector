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

    static var delegate: LeakInspectorDelegate?

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
        dispatch_after(delayTime, dispatch_get_main_queue()) {
            self.checkForLeaks()
            self.scheduleToRun()
        }
    }

    func checkForLeaks() {
        var removeRefs = [RefWatch]()

        // Check all the objects to verify they've been deinit'd/dealloc'd
        for refWatch in refsToWatch {
            if let ref: AnyObject = refWatch.ref {
                if (hasRefLikelyLeaked(refWatch)) {
                    alertThatRefHasLeaked(ref, name: refWatch.name)
                    removeRefs.append(refWatch)
                }
            } else {
                removeRefs.append(refWatch)
            }
        }

        // Remove objects that we no longer need to track
        for refWatch in removeRefs {
            for (index, aRefWatch) in enumerate(refsToWatch) {
                if refWatch === aRefWatch {
                    refsToWatch.removeAtIndex(index)
                    break
                }
            }
        }
    }

    private func hasRefLikelyLeaked(refWatch: RefWatch) -> Bool {
        let checkIntervalInSeconds: NSTimeInterval = 5
        var hasRefLikelyLeaked = false
        if (abs(refWatch.date.timeIntervalSinceNow) > checkIntervalInSeconds) {
            if let controller = refWatch.ref as? UIViewController {
                if (controller.parentViewController == nil && controller.navigationController == nil) {
                    hasRefLikelyLeaked = true;
                } else {
                    refWatch.date = NSDate().dateByAddingTimeInterval(checkIntervalInSeconds)
                }
            } else {
                hasRefLikelyLeaked = true
            }
        }
        return hasRefLikelyLeaked;
    }

    private func alertThatRefHasLeaked(ref: AnyObject, name: String) {
        NSLog("Leak Inspector: detected possible leak of %@", name)
        if let delegate = LeakInspector.delegate {
            delegate.didLeakReference(ref, name: name)
        }
    }
}