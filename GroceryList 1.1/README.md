# GroceryList — iOS App

A clean, production-ready grocery list app built with SwiftUI, targeting iOS 17+.

## Features

- **Add / Remove Items** — Tap the green "+ Add Item" FAB to add items; swipe to delete or long-press for a context menu
- **Radio Toggle (Active/Inactive)** — Tap the circle on the left of any item to mark it as collected; it moves to the "Completed" section with a strikethrough
- **Sub-items (Types/Variants)** — Tap the `⊕` button on any item to add sub-items (e.g. "Whole Milk", "2%" under "Milk"). Sub-items collapse/expand with the chevron badge
- **Quantity Stepper** — Every item and sub-item has a `−  N  +` stepper to increment/decrement quantity
- **Inline Sub-item Editing** — Double-tap any name to rename it in place
- **Search** — Filter items and sub-items live with the search bar
- **Progress Bar** — Visual progress tracker at the top shows how many items are collected
- **Persistent Storage** — List auto-saves to `UserDefaults` and restores on next launch
- **Context Menus** — Long-press any item for Rename / Add Sub-Item / Delete
- **Clear Actions** — "Clear Completed" or "Clear All" from the ⋯ menu

## Project Structure

```
GroceryList/
├── GroceryListApp.swift          # @main entry point
├── Info.plist
├── Assets.xcassets/              # Color assets (AppGreen, AppGreenLight, AppAccent)
├── Models/
│   └── GroceryModels.swift       # GroceryItem, SubItem, GroceryList structs
├── ViewModels/
│   └── GroceryListViewModel.swift # @MainActor ObservableObject, all business logic
└── Views/
    ├── ContentView.swift          # Main list screen
    ├── GroceryItemRow.swift       # Item card with sub-item expansion
    ├── SubItemRow.swift           # Individual sub-item row
    └── Components.swift           # Shared UI: RadioButton, QuantityStepper, AddItemSheet, etc.
```

## Setup

1. Open `GroceryList.xcodeproj` in Xcode 15+
2. In **Signing & Capabilities**, set your Team and Bundle ID (change `com.yourcompany.GroceryList`)
3. Select a simulator or device and press **Run** (⌘R)

## Requirements

- Xcode 15.0+
- iOS 17.0+ deployment target
- Swift 5.9+

## App Store Checklist

Before submitting:
- [ ] Replace bundle ID `com.yourcompany.GroceryList` with your own
- [ ] Add an `AppIcon` image set to `Assets.xcassets`
- [ ] Add a Launch Screen storyboard or keep `UILaunchScreen` dict in Info.plist
- [ ] Add Privacy Manifest (`PrivacyInfo.xcprivacy`) — app uses `UserDefaults` (NSPrivacyAccessedAPICategoryUserDefaults)
- [ ] Set your marketing version and build number in the target settings
- [ ] Test on multiple device sizes in the simulator

## Architecture

- **MVVM** — Models are pure value types (`Codable` structs), ViewModel owns all mutations, Views are stateless except for local UI state
- **@MainActor** — ViewModel runs on main actor; no data races
- **UserDefaults persistence** — Simple JSON encoding; can be upgraded to Core Data / CloudKit for iCloud sync
