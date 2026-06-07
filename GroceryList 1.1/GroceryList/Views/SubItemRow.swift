import SwiftUI

struct SubItemRow: View {
    let subItem: SubItem
    let itemID: UUID
    @ObservedObject var viewModel: GroceryListViewModel

    @State private var isEditing: Bool = false
    @State private var editName: String = ""
    @State private var swipeOffset: CGFloat = 0
    @State private var showDeleteButton: Bool = false
    @FocusState private var focused: Bool

    private let deleteRevealWidth: CGFloat = 72

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 2, height: 20)
                    .padding(.leading, 12)

                Button {
                    withAnimation(.spring(response: 0.2)) {
                        viewModel.toggleSubItem(itemID: itemID, subID: subItem.id)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(subItem.isChecked ? AppTheme.primaryLight : Color(.systemGray3), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                        if subItem.isChecked {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.primaryLight)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
                .buttonStyle(.plain)

                if isEditing {
                    TextField("Sub-item name", text: $editName)
                        .font(.system(size: 15))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { commitEdit() }
                } else {
                    Text(subItem.name)
                        .font(.system(size: 15))
                        .foregroundColor(subItem.isChecked ? .primary : .secondary)
                        .onTapGesture(count: 2) { beginEditing() }
                }

                Spacer()

                QuantityStepper(
                    value: subItem.quantity,
                    onIncrement: { viewModel.incrementSubItem(itemID: itemID, subID: subItem.id) },
                    onDecrement: { viewModel.decrementSubItem(itemID: itemID, subID: subItem.id) }
                )
                .opacity(subItem.isChecked ? 1 : 0.6)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .offset(x: swipeOffset)
            .gesture(swipeGesture)
            .contextMenu {
                Button { beginEditing() } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    viewModel.removeSubItem(from: itemID, subID: subItem.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Delete button sits to the RIGHT, outside the sliding content
            if showDeleteButton {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        viewModel.removeSubItem(from: itemID, subID: subItem.id)
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
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing))
            }
        }
        .clipped()
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: swipeOffset)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showDeleteButton)
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

    // MARK: - Helpers
    private func beginEditing() {
        editName = subItem.name
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }

    private func commitEdit() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            viewModel.updateSubItemName(itemID: itemID, subID: subItem.id, newName: trimmed)
        }
        isEditing = false
    }
}
