@objc protocol LeakInspectorDelegate {
    func didLeakReference(ref: AnyObject, name: String)
}

@objc protocol LeakInspectorIgnore {

}

@objc class LeakInspector {

    private class RefWatch {
        weak var ref: AnyObject?
        var name: String
        var date = NSDate()
        var failedChecks = 0

        init(ref: AnyObject, name: String) {
            self.ref = ref
            self.name = name
        }
    }

    static var delegate: LeakInspectorDelegate? {
        didSet {
            sharedInstance // forces the shared instance to initialize
        }
    }

    private static let sharedInstance = LeakInspector()
    private var refsToWatch = [RefWatch]()
    private let simulator = TARGET_IPHONE_SIMULATOR == 1
    private let frequency: NSTimeInterval = 3

    private init() {
        if simulator {
            swizzleViewDidLoad()
            scheduleToRun()
        }
    }

    class func watch(ref: AnyObject) {
        if sharedInstance.simulator {
            watch(ref, name: _stdlib_getDemangledTypeName(ref))
        }
    }

    class func watch(ref: AnyObject, name: String) {
        if sharedInstance.simulator {
            if NSThread.isMainThread() {
                sharedInstance.watch(ref, name: name)
            } else {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.sharedInstance.watch(ref, name: name)
                })
            }
        }
    }

    private func watch(ref: AnyObject, name: String) {
        if shouldWatch(ref) {
            var newRefToWatch = RefWatch(ref: ref, name: name)
            refsToWatch.append(newRefToWatch)
        }
    }

    private func shouldWatch(ref: AnyObject) -> Bool {
        if ref is LeakInspectorIgnore {
            return false
        }
        for refWatch in refsToWatch {
            if ref === refWatch.ref {
                return false
            }
        }
        return true
    }

    private func scheduleToRun() {
        let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(frequency * Double(NSEC_PER_SEC)))
        dispatch_after(delayTime, dispatch_get_main_queue()) {
            self.checkForLeaks()
            self.scheduleToRun()
        }
    }

    private func checkForLeaks() {
        var removeRefs = [RefWatch]()

        // Check all the objects to verify they've been deinit'd/dealloc'd
        for refWatch in refsToWatch {
            if let ref: AnyObject = refWatch.ref {
                if (hasRefLikelyLeaked(refWatch)) {
                    refWatch.failedChecks++
                    if (refWatch.failedChecks > 1) {
                        // To prevent pausing in the debugger from throwing a false positive we make it fail the check twice
                        alertThatRefHasLeaked(ref, name: refWatch.name)
                        removeRefs.append(refWatch)
                    }
                } else {
                    refWatch.failedChecks = 0
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
        var hasRefLikelyLeaked = false
        if (abs(refWatch.date.timeIntervalSinceNow) > frequency) {
            if let controller = refWatch.ref as? UIViewController {
                if (controller.parentViewController == nil && controller.navigationController == nil) {
                    hasRefLikelyLeaked = true;
                } else {
                    refWatch.date = NSDate().dateByAddingTimeInterval(frequency)
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

    private func swizzleViewDidLoad() {
        method_exchangeImplementations(
            class_getInstanceMethod(UIViewController.self, "loadView"),
            class_getInstanceMethod(UIViewController.self, "loadView_WithLeakInspector")
        )
    }
}

extension UIViewController {
    func loadView_WithLeakInspector() {
        LeakInspector.watch(self)
        loadView_WithLeakInspector()
    }
}