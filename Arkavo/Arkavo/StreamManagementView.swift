import SwiftData
import SwiftUI

struct StreamManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var accountManager: AccountManager
    @State private var showingCreateStream = false
    @State private var streams: [Stream] = []

    var body: some View {
        VStack {
              HStack {
                  Spacer()
                  
                  Text("My Streams")
                    .font(.title)
                    .padding(.leading, 50)
                  
                  Spacer()

                Button(action: {
                    showingCreateStream = true
                }, label: {
                    Image(systemName: "plus")
                        .font(.title)
                })
                .padding(.trailing, 20)
                  

            } //: HStack
            
            List {
 
                    ForEach(streams) { stream in
                        CompactStreamProfileView(viewModel: StreamProfileViewModel(profile: stream.profile, participantCount: 2))
                    }

            } //: LIST
            
            Spacer()
            
        } //: VStack
        .padding(.top, 100)
        .sheet(isPresented: $showingCreateStream) {
            CreateStreamProfileView { profile, _ in
                let newStream = Stream(name: profile.name, ownerID: accountManager.account.id, profile: profile)
                streams.append(newStream)
                accountManager.account.streams.append(newStream)
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save new stream: \(error)")
                }
            }
        }
        .onAppear {
            streams = accountManager.account.streams
        }
    }
}

struct StreamManagementView_Previews: PreviewProvider {
    static var previews: some View {
        StreamManagementView(accountManager: mockAccountManager())
            .modelContainer(for: [Account.self, Profile.self], inMemory: true)
    }

    static func mockAccountManager() -> AccountManager {
        let accountManager = AccountManager()

        // Create mock streams
        let profile1 = Profile(name: "Stream 1", blurb: "This is the first stream")
        let stream1 = Stream(name: "Stream 1", ownerID: accountManager.account.id, profile: profile1)

        let profile2 = Profile(name: "Stream 2", blurb: "This is the second stream")
        let stream2 = Stream(name: "Stream 2", ownerID: accountManager.account.id, profile: profile2)

        let profile3 = Profile(name: "Stream 3", blurb: "This is the third stream")
        let stream3 = Stream(name: "Stream 3", ownerID: accountManager.account.id, profile: profile3)

        // Add mock streams to the account
        accountManager.account.streams = [stream1, stream2, stream3]

        return accountManager
    }
}
