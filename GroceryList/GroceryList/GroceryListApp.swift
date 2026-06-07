import SwiftUI

@main
struct GroceryListApp: App {
    @StateObject private var viewModel = GroceryListViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .tint(Color("AppGreen"))
                .onOpenURL { url in
                    if url.scheme == "grocerylist" && url.host == "import" {
                        viewModel.importFromDeepLink(url: url)
                    } else {
                        // Handle file import (existing behavior)
                        viewModel.importList(from: url)
                    }
                }
        }
    }
}
