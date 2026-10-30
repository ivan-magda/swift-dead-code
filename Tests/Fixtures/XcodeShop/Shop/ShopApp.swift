import Feature
import ShopCore
import SwiftUI

@main
struct ShopApp: App {
  var body: some Scene {
    WindowGroup {
      VStack {
        Text(Banner.title + Feature.name)
        Image("UsedImage")
      }
    }
  }
}
