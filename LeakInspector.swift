@objc protocol LeakInspectorDelegate {
    func didLeakReference(ref: AnyObject, name: String)
}

@objc protocol LeakInspectorIgnore {

}

class LeakInspector: NSObject {

    private class RefWatch {
        weak var ref: AnyObject?
        let name: String
        let ignore: Bool
        var failedChecks = 0

        init(ref: AnyObject, name: String, ignore: Bool) {
            self.ref = ref
            self.name = name
            self.ignore = ignore
        }
    }

    static var delegate: LeakInspectorDelegate? {
        didSet {
            sharedInstance // forces the shared instance to initialize
        }
    }

    private static let sharedInstance = LeakInspector()
    private var refsToWatch = [RefWatch]()
    private var classesToIgnore = [AnyObject.Type]()
    private let simulator = TARGET_IPHONE_SIMULATOR == 1
    private let frequency: NSTimeInterval = 3

    private override init() {
        super.init()
        if simulator {
            swizzleViewDidLoad()
            scheduleToRun()
        }
    }

    class func watch(ref: AnyObject) {
        if sharedInstance.simulator {
            register(ref, name: _stdlib_getDemangledTypeName(ref), ignore: false)
        }
    }

    class func ignore(ref: AnyObject) {
        if sharedInstance.simulator {
            register(ref, name: _stdlib_getDemangledTypeName(ref), ignore: true)
        }
    }

    class func ignoreClass(type: AnyObject.Type) {
        if sharedInstance.simulator {
            if NSThread.isMainThread() {
                sharedInstance.ignoreClass(type)
            } else {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.sharedInstance.ignoreClass(type)
                })
            }
        }
    }

    private class func register(ref: AnyObject, name: String, ignore: Bool) {
        if sharedInstance.simulator {
            if NSThread.isMainThread() {
                sharedInstance.register(ref, name: name, ignore: ignore)
            } else {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.sharedInstance.register(ref, name: name, ignore: ignore)
                })
            }
        }
    }

    private func ignoreClass(type: AnyObject.Type) {
        for (index, clazz) in classesToIgnore.enumerate() {
            if clazz === type {
                classesToIgnore.removeAtIndex(index)
                break
            }
        }
        classesToIgnore.append(type.self)
    }

    private func register(ref: AnyObject, name: String, ignore: Bool) {
        if shouldWatch(ref) {
            let newRefToWatch = RefWatch(ref: ref, name: name, ignore: ignore)
            // Check to see if we're already watching this ref and remove the old RefWatch if so
            for (index, aRefWatch) in refsToWatch.enumerate() {
                if aRefWatch.ref === ref {
                    refsToWatch.removeAtIndex(index)
                    break
                }
            }
            refsToWatch.append(newRefToWatch)
        }
    }

    private func shouldWatch(ref: AnyObject) -> Bool {
        if ref is LeakInspectorIgnore {
            return false
        }

        for clazz in classesToIgnore {
            if ref.dynamicType === clazz.self {
                return false
            }
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
                        // Make objects fail twice before we report them to get async objects a chance to dealloc
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
            for (index, aRefWatch) in refsToWatch.enumerate() {
                if refWatch === aRefWatch {
                    refsToWatch.removeAtIndex(index)
                    break
                }
            }
        }
    }

    private func hasRefLikelyLeaked(refWatch: RefWatch) -> Bool {
        if (refWatch.ignore) {
            return false
        }

        if let controller = refWatch.ref as? UIViewController {
            if controller.parentViewController == nil && controller.navigationController == nil && controller.presentingViewController == nil && refWatch.name != "UIApplicationRotationFollowingController" {
                return true
            }
        } else {
            return true
        }
        
        return false
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