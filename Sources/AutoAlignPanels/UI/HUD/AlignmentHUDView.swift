import SwiftUI

struct AlignmentHUDView: View {
    let content: AlignmentFeedbackCenter.HUDContent?

    var body: some View {
        if let content {
            HStack(spacing: 12) {
                icon(for: content.style)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.primary)
                        .font(.headline)
                        .lineLimit(2)
                    if let secondary = content.secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
            .shadow(radius: 12, y: 4)
            .padding(16)
        }
    }

    // Errors and warnings carry a symbol shape plus text — never color alone.
    @ViewBuilder
    private func icon(for style: AlignmentFeedbackCenter.HUDContent.Style) -> some View {
        switch style {
        case .success(let symbolName):
            Image(systemName: symbolName)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
        case .warning(let symbolName):
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: 4)
                }
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.orange)
        case .info(let symbolName):
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
