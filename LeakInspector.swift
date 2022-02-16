import UIKit

@objc protocol LeakInspectorDelegate {
    func didLeakReference(_ ref: AnyObject, name: String)
}

@objc protocol LeakInspectorIgnore {

}

@objcMembers
class LeakInspector: NSObject {

    private class RefWatch: CustomStringConvertible {
        weak var ref: AnyObject?
        let name: String
        let ignore: Bool
        var failedChecks = 0
        var description: String { return "LeakInspector.RefWatch(name: \(name), ignore: \(ignore), failedChecks: \(failedChecks))" }

        init(ref: AnyObject, name: String, ignore: Bool) {
            self.ref = ref
            self.name = name
            self.ignore = ignore
        }
    }

    static var delegate: LeakInspectorDelegate? {
        didSet {
            _ = sharedInstance // forces the shared instance to initialize
        }
    }

    private static let sharedInstance = LeakInspector()
    private var refsToWatch = [RefWatch]()
    private var classesToIgnore = [AnyObject.Type]()
    private let simulator = TARGET_IPHONE_SIMULATOR == 1
    private let frequency = 3 // seconds

    private override init() {
        super.init()
        if simulator {
            swizzleViewDidLoad()
            scheduleToRun()
        }
    }

    class func watch(_ ref: AnyObject) {
        if sharedInstance.simulator {
            register(ref, name: String(describing: ref.self), ignore: false)
        }
    }

    class func ignore(_ ref: AnyObject) {
        if sharedInstance.simulator {
            unregister(ref)
            register(ref, name: String(describing: ref.self), ignore: true)
        }
    }

    class func rewatch(_ ref: AnyObject) {
        // If you've ignored a ref and want to start watching it again
        if sharedInstance.simulator {
            unregister(ref)
            register(ref, name: String(describing: ref.self), ignore: false)
        }
    }

    class func ignoreClass(_ type: AnyObject.Type) {
        if sharedInstance.simulator {
            if Thread.isMainThread {
                sharedInstance.ignoreClass(type)
            } else {
                DispatchQueue.main.async {
                    self.sharedInstance.ignoreClass(type)
                }
            }
        }
    }

    private class func unregister(_ ref: AnyObject) {
        if sharedInstance.simulator {
            if Thread.isMainThread {
                sharedInstance.unregister(ref)
            } else {
                DispatchQueue.main.async {
                    self.sharedInstance.unregister(ref)
                }
            }
        }
    }

    private class func register(_ ref: AnyObject, name: String, ignore: Bool) {
        if sharedInstance.simulator {
            if Thread.isMainThread {
                sharedInstance.register(ref, name: name, ignore: ignore)
            } else {
                DispatchQueue.main.async {
                    self.sharedInstance.register(ref, name: name, ignore: ignore)
                }
            }
        }
    }

    private func ignoreClass(_ type: AnyObject.Type) {
        for index in 0..<classesToIgnore.count {
            let clazz: AnyClass = classesToIgnore[index]
            if clazz === type {
                classesToIgnore.remove(at: index)
                break
            }
        }
        classesToIgnore.append(type.self)
    }

    private func unregister(_ ref: AnyObject) {
        for (index, aRefWatch) in refsToWatch.enumerated() {
            if aRefWatch.ref === ref {
                refsToWatch.remove(at: index)
                break
            }
        }
    }

    private func register(_ ref: AnyObject, name: String, ignore: Bool) {
        if shouldWatch(ref) {
            let newRefToWatch = RefWatch(ref: ref, name: name, ignore: ignore)
            // Check to see if we're already watching this ref and remove the old RefWatch if so
            for (index, aRefWatch) in refsToWatch.enumerated() {
                if aRefWatch.ref === ref {
                    refsToWatch.remove(at: index)
                    break
                }
            }
            refsToWatch.append(newRefToWatch)
        }
    }

    private func shouldWatch(_ ref: AnyObject) -> Bool {
        guard !String(describing: ref).contains("UIApplicationRotationFollowingController") else { return false }
        guard !String(describing: ref).contains("UIInputWindowController") else { return false }
        guard !String(describing: ref).contains("_UIAlertControllerTextFieldViewController") else { return false }
        guard !String(describing: ref).contains("UISystemKeyboardDockController") else { return false }
        guard !String(describing: ref).contains("UICompatibilityInputViewController") else { return false }
        guard !String(describing: ref).contains("UIAlertController") else { return false }
        guard !String(describing: ref).contains("GCKUIGuestModePairingViewController") else { return false }

        if ref is LeakInspectorIgnore {
            return false
        }

        for clazz in classesToIgnore {
            if type(of: ref) === clazz.self {
                return false
            }
        }

        if type(of: ref) === UIViewController.self {
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
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(frequency)) {
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
                    refWatch.failedChecks += 1
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
            for (index, aRefWatch) in refsToWatch.enumerated() {
                if refWatch === aRefWatch {
                    refsToWatch.remove(at: index)
                    break
                }
            }
        }
    }

    private func hasRefLikelyLeaked(_ refWatch: RefWatch) -> Bool {
        if (refWatch.ignore) {
            return false
        }

        if let controller = refWatch.ref as? UIViewController {
            if controller.parent == nil && controller.navigationController == nil && controller.presentingViewController == nil && controller.view.window?.rootViewController != controller {
                return true
            }
        } else {
            return true
        }

        return false
    }

    private func alertThatRefHasLeaked(_ ref: AnyObject, name: String) {
        NSLog("Leak Inspector: detected possible leak of %@", name)
        if let delegate = LeakInspector.delegate {
            delegate.didLeakReference(ref, name: name)
        }
    }

    private func swizzleViewDidLoad() {
        method_exchangeImplementations(
            class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewDidLoad))!,
            class_getInstanceMethod(UIViewController.self, #selector(UIViewController.loadView_WithLeakInspector))!
        )
    }
}

extension UIViewController {
    @objc func loadView_WithLeakInspector() {
        LeakInspector.watch(self)
        loadView_WithLeakInspector()
    }
}
