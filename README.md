# LeakInspector

An iOS memory leak detection tool to help you prevent leaking UIViewControllers (and any other object you want to track to make sure it gets deallocated when expected). It only runs when running in the iOS simulator and short circuits on device so you don't need to worry about it running in your production app.

LeakInspector is written in Swift but works on Objective-C projects too. This project was inspired by [Square's Leak Canary](https://github.com/square/leakcanary) for Android. At [Two Bit Labs](http://twobitlabs.com) we use Leak Canary on our Android projects and have been so impressed with how it helped us catch memory leaks during the development cycle that we wanted a similar tool for the iOS apps we work on.

This was a very quick proof of concept so there's a lot of room for improvement to make it more robust and helpful in identifying the source of a leak. 

## How to use it

At the moment we don't have Cocoapods or Carthage support so you'll need to git submodule it or just download a zip and drop the files directly into your project:

* [Download the latest zip file](https://github.com/twobitlabs/LeakInspector/archive/master.zip)

### Initialization

In your application delegate, register the alert provider to show a UIAlertController popup whenever a possible leak is found:

Objective-C:

```
[LeakInspector setDelegate:[LeakInspectorAlertProvider new]];
```

Swift:

```
LeakInspector.delegate = LeakInspectorAlertProvider()
```

If you'd rather do something else when a leak is found just set the delegate to be your own app delegate or some other class that implements the LeakInspectorDelegate protocol. LeakInspector keeps a strong reference to its delegate so that you can set it and forget it (but something to keep in mind if you implement your own delegate).

### Watching UIViewControllers for memory leaks

Next, start tracking controllers for memory leaks. In all of our projects we have a BaseController that is a subclass of UIViewController (for analytics and such) so we only have to add this code in one place. If you subclass directly from UIViewController you'll have to add this to every controller (or some other shared code that gets called from every controller). It can go in any method such as viewDidLoad, viewWillAppear, init, etc. We like to put it in viewDidLoad but up to you:

Objective-C:

```
[LeakInspector watchRef:self];
```

Swift:

```
LeakInspector.watchRef(self)
```

Leak Inspector keeps a weak reference to any objects it tracks and will check all registered controllers every 5 seconds. If it finds a controller that has not deallocated but has a null navigationController or parentController it will flag it as a possible leak. 

You may have legitimate cases in your app where you remove a controller but want to hang on to it, if so you'll need to NOT register that controller with Leak Inspector. Feel free to submit a pull request with an alternative solution for that issue if you run into it.

### Watching any other kinds of object for memory leaks

When you are done using an object and want to be sure it gets deallocated just register it with LeakInspector. For example if you have some object that you know does a lot with blocks, GCD, etc that you want to make sure always gets cleaned up just track it:

Objective-C:

```
[self.pollingManager stopPolling];
[LeakInspector watchRef:self.pollingManager]; // Start tracking it and Leak Inspector will warn you if it doesn't get deallocated 
self.pollingManager = nil;
```

Swift:

```
pollingManager.stopPolling()
LeakInspector.watchRef(pollingManager)
pollingManager = nil
```


## Contributing

We love pull requests with bug fixes, features, and documentation updates! 

Feel free to add your name and link under the contributors section as part of your pull request so that way if we merge it you get credit as well!

## Contributors
 - [Two Bit Labs](http://twobitlabs.com/)
 - [Todd Huss](https://github.com/thuss)

