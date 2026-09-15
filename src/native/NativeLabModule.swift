import ExpoModulesCore
import UIKit

public class NativeLabModule: Module {
  public func definition() -> ModuleDefinition {
    // JavaScript can call this synchronously.
    Function("greet") { (name: String) -> String in
      return "Hello \(name)! This message came from Swift."
    }

    // UIKit-related work should run on the main queue.
    AsyncFunction("getDeviceInfo") { () -> [String: String] in
      return [
        "name": UIDevice.current.name,
        "system": UIDevice.current.systemName,
        "version": UIDevice.current.systemVersion
      ]
    }
    .runOnQueue(.main)
  }
} 
