## 0.0.39
Updated native code.

## 0.0.38
Fix bug in getting instance.
Improve performance for request local network.

## 0.0.34
Request access for local network in ios.


## 0.0.40
Upgrade dependencies 
Enhance code quality and eliminate unnecessary code.

## 0.0.41
Include ZebraUtilPlugin.java in the repository.

## 0.1.41 
Avoid duplicate devices.
Improve list devices example.

## 0.2.41
Update view based on printer state.

## 0.3.41
Dynamically disconnect the current printer when the user selects a different one.
Change the color and update the state once the printer is disconnected.

## 1.3.41
* Automatic Bluetooth Device Scanning:

Implemented continuous scanning for nearby Bluetooth devices to improve device discovery without manual intervention.
Added background listening for Bluetooth device connections and disconnections, ensuring real-time updates for device availability.

* Code Quality Enhancements:

Refactored Bluetooth scanning logic to optimize memory usage and prevent potential memory leaks.
Improved thread management to prevent excessive thread creation during Bluetooth operations.
Applied coding best practices, including proper resource management and context handling, to improve maintainability and performance.

## 1.4.41
* Support Spanish language.
* Synchronize printer once the scan has been restarted.

## 1.4.42
* Fix error in Printer class, devices were duplicated.
* Persist printer connected.

## 1.4.43
* Add `ZebraStatus` enum and `statusEnum` field to `ZebraDevice`.
* Normalize native status strings (iOS/Android, localized) into enum.
* Update controller to keep `status` and `statusEnum` in sync.
* Android: `connectToPrinter` now returns `true/false` to Flutter based on connection success.
