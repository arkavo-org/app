import AuthenticationServices
import Foundation

#if canImport(UIKit)
import UIKit
typealias MyApp = UIApplication
#elseif canImport(AppKit)
import AppKit
typealias MyApp = NSApplication
#endif

#if os(iOS)
typealias MyWindow = UIWindow
#elseif os(macOS)
typealias MyWindow = NSWindow
#endif

class AuthenticationManagerViewModel: ObservableObject {
    @Published var authenticationManager = AuthenticationManager()
}

class AuthenticationManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var currentChallenge: String?
    private var rawChallenge: Data?
    private var sessionCookie: HTTPCookie?
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        print("presentationAnchor called")
        
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else {
            fatalError("No window found in the current window scene")
        }
        return window
        #elseif os(macOS)
        guard let window = NSApplication.shared.windows.first
        else {
            fatalError("No window found in the application")
        }
        return window
        #else
        fatalError("Unsupported platform")
        #endif
    }
    
    func signUp(accountName: String) {
        guard !accountName.isEmpty else {
            print("Account name cannot be empty")
            return
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "webauthn.arkavo.net")
        registrationOptions(accountName: accountName) { [weak self] challenge, userID in
            guard let self = self else { return }
            guard let challengeData = challenge, let userIDData = userID else {
                print("Either challenge or userID is nil.")
                return
            }
            // Store the raw challenge data
            self.rawChallenge = challengeData
            print("Raw challenge data: \(challengeData.map { String(format: "%02hhx", $0) }.joined())")
            
            // Store the challenge as a base64 encoded string
            self.currentChallenge = challengeData.base64URLEncodedString()
            print("Received challenge (base64): \(self.currentChallenge ?? "nil")")
            print("Received challenge: \(self.currentChallenge ?? "nil")")
            let publicKeyCredentialRequest = provider.createCredentialRegistrationRequest(challenge: challengeData, name: accountName, userID: userIDData)
            let controller = ASAuthorizationController(authorizationRequests: [publicKeyCredentialRequest])
            controller.delegate = self
            controller.presentationContextProvider = self
            DispatchQueue.main.async {
                controller.performRequests()
            }
        }
    }
    
    func registrationOptions(accountName: String, completion: @escaping (Data?, Data?) -> Void) {
        let url = URL(string: "https://webauthn.arkavo.net/challenge/\(accountName)")!
        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Error fetching registration options: \(error.localizedDescription)")
                completion(nil, nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse,
               let fields = httpResponse.allHeaderFields as? [String: String] {
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
                if let cookie = cookies.first(where: { $0.name == "authnz-rs" }) {
                    self?.sessionCookie = cookie
                    print("Received session cookie: \(cookie)")
                }
            }
            
            if let data = data {
                do {
                    if let challenge = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let publicKey = challenge["publicKey"] as? [String: Any],
                       let challengeStr = publicKey["challenge"] as? String,
                       let userDict = publicKey["user"] as? [String: Any],
                       let userIDStr = userDict["id"] as? String
                    {
                        let challenge = challengeStr.data(using: .utf8)
                        let accountID = userIDStr.data(using: .utf8)
                        completion(challenge, accountID)
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
        // Handle successful signIn
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("Authorization completed successfully")
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            sendRegistrationDataToServer(credential: credential)
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Authorization failed: \(error.localizedDescription)")
        print("Authorization process failed in Authentication Manager.")
        print("Error occurred: ", error)
        debugPrint("Error details: \(error.localizedDescription)")
        print("Now entering failed authorization handling.")
        // Handle failed authorization
        print("Failed authorization has been handled.")
    }
    
    private func sendRegistrationDataToServer(credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) {
        print("sendRegistrationDataToServer")
        let url = URL(string: "https://webauthn.arkavo.net/register_finish")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // cookie
//        if let cookie = sessionCookie {
//            request.setValue(cookie.value, forHTTPHeaderField: "Cookie")
//            print("Sending cookie: \(cookie.name)=\(cookie.value)")
//        }
        // Decode the clientDataJSON to verify the challenge
        if let clientDataJSONString = String(data: credential.rawClientDataJSON, encoding: .utf8),
           let clientDataJSON = try? JSONSerialization.jsonObject(with: credential.rawClientDataJSON, options: []) as? [String: Any],
           let challenge = clientDataJSON["challenge"] as? String {
            print("Client data JSON: \(clientDataJSONString)")
            print("Extracted challenge: \(challenge)")
            print("Stored challenge: \(currentChallenge ?? "nil")")
            
            if challenge != currentChallenge {
                print("Warning: Challenge mismatch")
            } else {
                print("Challenge match confirmed")
            }
        }
        // Print raw challenge data again for comparison
        print("Raw challenge data (for comparison): \(rawChallenge?.map { String(format: "%02hhx", $0) }.joined() ?? "nil")")
        let parameters: [String: Any] = [
            "id": credential.credentialID.base64URLEncodedString(),
            "rawId": credential.credentialID.base64URLEncodedString(),
            "response": [
                "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                "attestationObject": credential.rawAttestationObject!.base64URLEncodedString()
            ],
            "type": "public-key",
            "extensions": [:] // Add any extensions if needed
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            print("Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to print request body")")
        } catch {
            print("Error creating JSON data: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error sending registration data: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received from server")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("Server response: \(responseString)")
                
                // Try to parse the response as JSON
                do {
                    if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        print("Parsed JSON response: \(jsonResult)")
                    }
                } catch {
                    print("Failed to parse JSON data. Error: \(error)")
                }
            }
        }.resume()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
