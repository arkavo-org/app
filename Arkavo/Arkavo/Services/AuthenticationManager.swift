import AuthenticationServices
import Foundation

#if canImport(UIKit)
    import UIKit
    typealias MyApp = UIApplication
#elseif canImport(AppKit)
    import AppKit
    typealias MyApp = NSApplication
#endif

class AuthenticationManagerViewModel: ObservableObject {
    @Published var authenticationManager = AuthenticationManager()
}

class AuthenticationManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        MyApp.shared.windows.first { $0.isKeyWindow }!
    }

    func signUp() {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "webauthn.arkavo.net")
        registrationOptions { challenge, userID in
            guard let challengeData = challenge, let userIDData = userID else {
                print("Either challenge or userID is nil.")
                return
            }
            let publicKeyCredentialRequest = provider.createCredentialRegistrationRequest(challenge: challengeData, name: "Blob", userID: userIDData)
            let controller = ASAuthorizationController(authorizationRequests: [publicKeyCredentialRequest])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func registrationOptions(completion: @escaping (Data?, Data?) -> Void) {
        let url = URL(string: "https://webauthn.arkavo.net/generate-registration-options")!
        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        session.dataTask(with: request) { data, _, error in

            if error != nil {
                print("Error occurred while making a request. \(error!.localizedDescription)")
                completion(nil, nil)
                return
            }

            if let data = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let challengeStr = json["challenge"] as? String,
                       let userDict = json["user"] as? [String: Any],
                       let userIDStr = userDict["id"] as? String
                    {
                        print("json selected")
                        let challenge = challengeStr.data(using: .utf8)
                        let userID = userIDStr.data(using: .utf8)
                        completion(challenge, userID)
                    } else {
                        print("Received data is not JSON or the format is not as expected: \(data)")
                        completion(nil, nil)
                    }
                } catch {
                    print("Failed to parse JSON data. \(error)")
                    completion(nil, nil)
                }
            }
        }
        .resume()
    }

    func signIn() {
        // You can implement the sign-in functionality similar to the signUp() method
        // But keep in mind you'll most likely have to use createCredentialAssertionRequest instead of createCredentialRegistrationRequest
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithAuthorization _: ASAuthorization) {
        // Handle successful authorization
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        // Log the error and point of failure and then handle the failed authorization
        print("Authorization process failed in Authentication Manager.")
        print("Error occurred: ", error)
        debugPrint("Error details: \(error.localizedDescription)")
        print("Now entering failed authorization handling.")
        // Handle failed authorization
        print("Failed authorization has been handled.")
    }
}
