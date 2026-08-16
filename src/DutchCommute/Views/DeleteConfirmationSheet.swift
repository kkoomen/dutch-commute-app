import SwiftUI

/// Bottom confirmation for deleting a journey: a sheet pinned to the
/// bottom of the screen (fixed position, drag handle), with the
/// destructive action prominent. Used by the journey list (swipe-to-
/// delete) and the edit-journey page.
struct DeleteConfirmationSheet: View {
    /// Called after the user confirms; the sheet dismisses itself first.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Delete journey?")
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text("This journey will be permanently removed.")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)

            Button(role: .destructive) {
                dismiss()
                onDelete()
            } label: {
                Text("Delete")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
}
