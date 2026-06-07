import SwiftUI

struct GroceryItemRow: View {
    let item: GroceryItem
    @ObservedObject var viewModel: GroceryListViewModel

    @Binding var isParentAdding: Bool
    @State private var showAddSubItem: Bool = false
    @State private var isEditing: Bool = false
    @State private var editName: String = ""
    @State private var swipeOffset: CGFloat = 0
    @State private var showDeleteButton: Bool = false
    @FocusState private var nameFocused: Bool

    private let deleteRevealWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button revealed behind the row
            deleteBackground

            // Main card — slides left on swipe
            VStack(spacing: 0) {
                mainRow

                if item.isExpanded && item.hasSubItems {
                    VStack(spacing: 0) {
                        ForEach(item.subItems) { sub in
                            SubItemRow(subItem: sub, itemID: item.id, viewModel: viewModel)
                            if sub.id != item.subItems.last?.id {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                    .clipped()
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showAddSubItem {
                    AddSubItemInline(
                        isShowing: $showAddSubItem,
                        onAdd: { name, qty in
                            viewModel.addSubItem(to: item.id, name: name, quantity: qty)
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: showAddSubItem) { _, newValue in
                if !newValue { isParentAdding = false}
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: .black.opacity(showDeleteButton ? 0 : 0.1),
                    radius: AppTheme.cardShadowRadius,
                    y: AppTheme.cardShadowY)
            .offset(x: swipeOffset)
            .gesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: swipeOffset)
    }

    // MARK: - Delete background
    @ViewBuilder
    private var deleteBackground: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.25)) {
                    viewModel.removeItem(id: item.id)
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: deleteRevealWidth)
            }
            .buttonStyle(.plain)
        }
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(Color.red)
        )
        .opacity(showDeleteButton ? 1 : 0)
    }

    // MARK: - Swipe gesture
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard value.translation.width < 0 else { return }
                let drag = min(0, value.translation.width)
                swipeOffset = max(drag, -deleteRevealWidth - 8)
                showDeleteButton = swipeOffset < -8
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    swipeOffset = 0
                    showDeleteButton = false
                    return
                }
                if value.translation.width < -(deleteRevealWidth * 0.5) {
                    swipeOffset = -deleteRevealWidth
                    showDeleteButton = true
                } else {
                    swipeOffset = 0
                    showDeleteButton = false
                }
            }
    }

    // MARK: - Main row
    @ViewBuilder
    private var mainRow: some View {
        HStack(spacing: 12) {
            RadioButton(isActive: item.isActive) {
                if showDeleteButton {
                    swipeOffset = 0
                    showDeleteButton = false
                } else {
                    withAnimation(.spring(response: 0.25)) {
                        viewModel.toggleItemActive(id: item.id)
                    }
                }
            }
            .padding(.leading, 4)

            if isEditing {
                TextField("Item name", text: $editName)
                    .font(.system(size: 16, weight: .medium))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitNameEdit() }
            } else {
                Text(item.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(item.isActive ? .secondary : .primary)
                    .onTapGesture {
                        if showDeleteButton {
                            withAnimation(.spring(response: 0.2)) {
                                swipeOffset = 0
                                showDeleteButton = false
                            }
                        }
                    }
                    .onTapGesture(count: 2) { beginNameEdit() }
            }

            Spacer()

            if item.subItems.isEmpty {
                QuantityStepper(
                    value: item.quantity,
                    onIncrement: { viewModel.incrementItem(id: item.id) },
                    onDecrement: { viewModel.decrementItem(id: item.id) }
                )
                .opacity(item.isActive ? 0.6 : 1)
            }

            HStack(spacing: 4) {
                if item.hasSubItems {
                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            viewModel.toggleExpanded(id: item.id)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("\(item.subItems.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Image(systemName: item.isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(AppTheme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.primary.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.spring(response: 0.2)) {
                        showAddSubItem.toggle()
                        isParentAdding = showAddSubItem
                        if !item.isExpanded {
                            viewModel.toggleExpanded(id: item.id)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.primary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button { beginNameEdit() } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                withAnimation { showAddSubItem.toggle() }
                isParentAdding = showAddSubItem
            } label: {
                Label("Add Sub-Item", systemImage: "plus.circle")
            }
        }
        .onTapGesture {
            if showDeleteButton {
                withAnimation(.spring(response: 0.2)) {
                    swipeOffset = 0
                    showDeleteButton = false
                }
            }
        }
    }

    // MARK: - Helpers
    private func beginNameEdit() {
        editName = item.name
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true }
    }

    private func commitNameEdit() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            viewModel.updateItemName(id: item.id, newName: trimmed)
        }
        isEditing = false
    }
}

// MARK: - Inline add sub-item
struct AddSubItemInline: View {
    @Binding var isShowing: Bool
    var onAdd: (String, Int) -> Void

    @State private var name: String = ""
    @State private var quantity: Int = 1
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(AppTheme.primaryLight)
                .frame(width: 2, height: 20)
                .padding(.leading, 12)

            TextField("Sub-item name", text: $name)
                .font(.system(size: 15))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { submit() }

            QuantityStepper(
                value: quantity,
                onIncrement: { quantity += 1 },
                onDecrement: { if quantity > 1 { quantity -= 1 } }
            )

            Button(action: submit) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(name.isEmpty ? .secondary : AppTheme.primary)
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                withAnimation { isShowing = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 12)
        .background(AppTheme.primary.opacity(0.1))
        .onAppear { focused = true }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed, quantity)
        name = ""
        quantity = 1
        focused = true
    }
}
