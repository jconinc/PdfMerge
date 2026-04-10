import SwiftUI

struct SplitEveryNView: View {
    @ObservedObject var viewModel: SplitViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Split Every N Pages")
                .font(.headline)

            HStack(spacing: 12) {
                Text("Pages per file:")
                    .font(.callout)

                Stepper(
                    value: $viewModel.everyNPages,
                    in: 1...max(viewModel.pageCount, 1)
                ) {
                    Text("\(viewModel.everyNPages)")
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 30, alignment: .trailing)
                }
            }

            if !viewModel.everyNPreview.isEmpty {
                Text(viewModel.everyNPreview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}
