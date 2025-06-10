import SwiftUI

struct AccountProfileBadge: View {
    @StateObject var viewModel: AccountProfileViewModel
    @State private var isExpanded = false
    @State private var rotationAngle: Double = 0

    var body: some View {
        VStack {
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        viewModel.profileImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())

                        if viewModel.profile.hasHighIdentityAssurance {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    }

                    Text(viewModel.profile.name)
                        .font(.headline)

                    HStack {
                        Text("Topic Tags:")
                            .font(.subheadline)
                            .bold()
                        ForEach(viewModel.topicTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(5)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(5)
                        }
                    }

                    Text("Location: \(String(describing: viewModel.profile.location))")

                    if viewModel.profile.hasHighEncryption {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.green)
                            .font(.title)
                            .rotationEffect(.degrees(rotationAngle))
                            .onAppear {
                                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                    rotationAngle = 360
                                }
                            }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .shadow(radius: 5)
            } else {
                HStack {
                    viewModel.profileImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())

                    Text(viewModel.profile.name)
                        .font(.caption)
                        .foregroundColor(.primary)

                    if viewModel.profile.hasHighIdentityAssurance {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            }
        }
    }
}
