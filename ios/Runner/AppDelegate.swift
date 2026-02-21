import UIKit
import Flutter
import GoogleMaps // 1. เพิ่มบรรทัดนี้

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 2. เพิ่มบรรทัดนี้ (ใส่ Key ของคุณ)
    GMSServices.provideAPIKey("AIzaSyBTPvi3gaQUwk-wsXzTeIhv8OknzH4qLSE")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}