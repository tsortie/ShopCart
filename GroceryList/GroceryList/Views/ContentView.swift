import SwiftUI

struct ContentView: View {
    
    @ObservedObject var viewModel: GroceryListViewModel
    @State private var showUndoBanner: Bool = false
    @State private var undoTask: Task<Void, Never>? = nil
    @State private var showImportPicker: Bool = false
    @State private var isAddingSubItem: Bool = false
    @State private var previousListIndex: Int = 0
    @State private var showAddList: Bool = false
    @State private var newListName: String = ""
    @State private var showRenameList: Bool = false
    @State private var renameText: String = ""
    @State private var isAddingItem: Bool = false
    @State private var newItemName: String = ""
    @State private var newItemQuantity: Int = 1
    @FocusState private var addFieldFocused: Bool
    @FocusState private var addListFieldFocused: Bool

    var body: some View {
        ZStack {
            listView
                .id(viewModel.selectedListIndex)
                .transition(.asymmetric(
                    insertion: .push(from: viewModel.selectedListIndex > previousListIndex ? .trailing : .leading),
                    removal: .push(from: viewModel.selectedListIndex > previousListIndex ? .leading : .trailing)
                ))
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.init(filenameExtension: "grocerylist")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                viewModel.importList(from: url)
            case .failure:
                break
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: viewModel.selectedListIndex)
        .overlay(alignment: .bottom) { tabBar }
        .overlay(alignment: .bottom) {
            undoBanner
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showUndoBanner)
        }
        .sheet(isPresented: $showAddList) { addListSheet }
        .sheet(isPresented: $showRenameList) { renameListSheet }
    }
    // MARK: - Undo Delete
    @ViewBuilder
    private var undoBanner: some View {
        if showUndoBanner {
            HStack {
                Text("List deleted")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Button("Undo") {
                    viewModel.undoDeleteList()
                    showUndoBanner = false
                    undoTask?.cancel()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.primaryLight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(Color(.darkGray))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    // MARK: - List view (one per tab)
    @ViewBuilder
    private var listView: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            searchBar
                                .padding(.horizontal, 25)
                                .padding(.top, 20)
                                .padding(.bottom, 12)

                            if viewModel.activeItems.isEmpty && viewModel.inactiveItems.isEmpty && !isAddingItem {
                                EmptyStateView().padding(.top, 60)
                            } else {
                                activeSection
                                inactiveSection
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .contentMargins(.bottom, 120, for: .scrollContent)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: viewModel.list.items)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isAddingItem)
                    .onTapGesture {
                        if isAddingItem { cancelAddItem() }
                    }
                    .onChange(of: isAddingItem) { _, newValue in
                        if newValue {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.spring(response: 0.2)) {
                                    proxy.scrollTo("inlineAddRow", anchor: .center)
                                }
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.bottom, 120, for: .scrollContent)
                
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: viewModel.list.items)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isAddingItem)

                if !isAddingItem && !isAddingSubItem {
                    addButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 75)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .navigationTitle(viewModel.list.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            renameText = viewModel.list.name
                            showRenameList = true
                        } label: {
                            Label("Rename List", systemImage: "pencil")
                        }

                        if let url = viewModel.exportAsDeepLink() {
                            ShareLink(item: url) {
                                Label("Share List", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button {
                            showImportPicker = true
                        } label: {
                            Label("Import List", systemImage: "square.and.arrow.down")
                        }

                        Button(role: .destructive) {
                            let offsets = IndexSet(integer: viewModel.selectedListIndex)
                            withAnimation { viewModel.deleteList(at: offsets) }
                            // Show undo banner
                            showUndoBanner = true
                            undoTask?.cancel()
                            undoTask = Task {
                                try? await Task.sleep(for: .seconds(4))
                                if !Task.isCancelled {
                                    await MainActor.run {
                                        withAnimation {
                                            showUndoBanner = false
                                        }
                                        viewModel.clearUndoHistory()
                                    }
                                }
                            }
                        } label: {
                            Label("Delete List", systemImage: "trash.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(AppTheme.primary)
                    }
                }
            }
        }
    }

    // MARK: - Tab bar
    @ViewBuilder
    private var tabBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(viewModel.lists.enumerated()), id: \.element.id) { index, groceryList in
                            Button {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                    previousListIndex = viewModel.selectedListIndex
                                    viewModel.selectList(at: index)
                                }
                            } label: {
                                Text(groceryList.name)
                                    .font(.system(size: 14, weight: viewModel.selectedListIndex == index ? .semibold : .regular))
                                    .foregroundColor(viewModel.selectedListIndex == index ? .white : AppTheme.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(viewModel.selectedListIndex == index ? AppTheme.primary : AppTheme.primary.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)

                // Add list button
                Button {
                    newListName = ""
                    showAddList = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(AppTheme.primary)
                }
                .padding(.trailing, 16)
            }
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Add list sheet
    @ViewBuilder
    private var addListSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("List Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("e.g. Hardware Store", text: $newListName)
                        .font(.system(size: 17))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: AppTheme.smallRadius).fill(Color(.systemGray6)))
                        .focused($addListFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { commitAddList() }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showAddList = false }.foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") { commitAddList() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(newListName.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : AppTheme.primary)
                        .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { addListFieldFocused = true }
    }

    // MARK: - Rename list sheet
    @ViewBuilder
    private var renameListSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("List Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("List name", text: $renameText)
                        .font(.system(size: 17))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: AppTheme.smallRadius).fill(Color(.systemGray6)))
                        .submitLabel(.done)
                        .onSubmit { commitRename() }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Rename List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showRenameList = false }.foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { commitRename() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(renameText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : AppTheme.primary)
                        .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Active section
    @ViewBuilder
    private var activeSection: some View {
        if !viewModel.activeItems.isEmpty || isAddingItem {
            SectionHeader(title: "Active", count: viewModel.activeItems.count)

            LazyVStack(spacing: 4) {
                if isAddingItem {
                    inlineAddRow
                        .id("inlineAddRow")
                        .padding(.horizontal, 16)
                        .transition(.asymmetric(insertion: .push(from: .top), removal: .push(from: .top)))
                }
                ForEach(viewModel.activeItems) { item in
                    GroceryItemRow(item: item, viewModel: viewModel, isParentAdding: $isAddingSubItem)
                        .padding(.horizontal, 16)
                        .transition(.asymmetric(insertion: .push(from: .leading), removal: .push(from: .trailing)))
                }
            }
            .padding(.bottom, 16)
        }
    }
    // MARK: - Inactive section
    @ViewBuilder
    private var inactiveSection: some View {
        if !viewModel.inactiveItems.isEmpty {
            SectionHeader(title: "Inactive", count: viewModel.inactiveItems.count)

            LazyVStack(spacing: 4) {
                ForEach(viewModel.inactiveItems) { item in
                    GroceryItemRow(item: item, viewModel: viewModel, isParentAdding: $isAddingSubItem)
                        .padding(.horizontal, 16)
                        .transition(.asymmetric(insertion: .push(from: .trailing), removal: .push(from: .leading)))
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Inline add row
    @ViewBuilder
    private var inlineAddRow: some View {
        HStack(spacing: 12) {
            Button(action: commitAddItem) {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 2)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)

            TextField("Item name", text: $newItemName)
                .font(.system(size: 16, weight: .medium))
                .focused($addFieldFocused)
                .submitLabel(.done)
                .onSubmit { commitAddItem() }

            Spacer()

            QuantityStepper(
                value: newItemQuantity,
                onIncrement: { newItemQuantity += 1 },
                onDecrement: { if newItemQuantity > 1 { newItemQuantity -= 1 } }
            )

            Button(action: commitAddItem) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(newItemName.trimmingCharacters(in: .whitespaces).isEmpty ? Color(.systemGray4) : AppTheme.primary)
            }
            .buttonStyle(.plain)
            .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .shadow(color: AppTheme.primary.opacity(0.15), radius: 6, y: 2)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.primary.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Add item actions
    private func beginAddItem() {
        newItemName = ""
        newItemQuantity = 1
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { isAddingItem = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { addFieldFocused = true }
    }

    private func commitAddItem() {
        let trimmed = newItemName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            withAnimation(.spring(response: 0.2)) {
                viewModel.addItem(name: trimmed, quantity: newItemQuantity)
            }
        }
        cancelAddItem()
    }

    private func cancelAddItem() {
        guard isAddingItem else { return }
        addFieldFocused = false
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { isAddingItem = false }
        newItemName = ""
        newItemQuantity = 1
    }
    
    private func discardAddItem() {
        addFieldFocused = false
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { isAddingItem = false }
        newItemName = ""
        newItemQuantity = 1
    }

    private func commitAddList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        showAddList = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { viewModel.addList(name: trimmed) }
        }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        showRenameList = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            viewModel.renameList(id: viewModel.list.id, name: trimmed)
        }
    }

    // MARK: - Search bar
    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 15))
            TextField("Search items…", text: $viewModel.searchText).font(.system(size: 16))
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.system(size: 15))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        )
    }

    // MARK: - FAB
    @ViewBuilder
    private var addButton: some View {
        Button(action: beginAddItem) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                Text("Add Item").font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [AppTheme.primary, AppTheme.primary.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: AppTheme.primary.opacity(0.45), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView(viewModel: GroceryListViewModel())
}
