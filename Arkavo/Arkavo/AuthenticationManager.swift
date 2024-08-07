import AuthenticationServices
import CryptoKit
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
    @Published var authenticationManager: AuthenticationManager

    init(baseURL: URL) {
        authenticationManager = AuthenticationManager(baseURL: baseURL)
    }
}

class AuthenticationManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @Published var currentAccount: String?
    private let baseURL: URL
    private let relyingPartyIdentifier: String

    init(baseURL: URL) {
        self.baseURL = baseURL
        relyingPartyIdentifier = baseURL.host ?? "webauthn.arkavo.net"
        super.init()
    }

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
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

    private func handleServerResponse<T: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        successMessage: String,
        failureMessage: String,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        if let error {
            print("\(failureMessage): \(error.localizedDescription)")
            completion(.failure(error))
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let error = NSError(domain: "HTTPError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            completion(.failure(error))
            return
        }

        print("HTTP Status Code: \(httpResponse.statusCode)")

        guard let data else {
            let error = NSError(domain: "DataError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])
            completion(.failure(error))
            return
        }

        if (200 ... 299).contains(httpResponse.statusCode) {
            do {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                print(successMessage)
                completion(.success(decodedData))
            } catch {
                print("Failed to parse JSON data. Error: \(error)")
                completion(.failure(error))
            }
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            let error = NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            completion(.failure(error))
        }
    }

    func signUp(accountName: String) {
        guard !accountName.isEmpty else {
            print("Account name cannot be empty")
            return
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        registrationOptions(accountName: accountName) { [weak self] challenge, userID in
            guard let self else { return }
            guard let challengeData = challenge, let userIDData = userID else {
                print("Either challenge or userID is nil.")
                return
            }
            print("signUp challengeData \(challengeData)")
            let publicKeyCredentialRequest = provider.createCredentialRegistrationRequest(
                challenge: challengeData,
                name: accountName,
                userID: userIDData
            )
            let controller = ASAuthorizationController(authorizationRequests: [publicKeyCredentialRequest])
            controller.delegate = self
            controller.presentationContextProvider = self
            DispatchQueue.main.async {
                controller.performRequests()
            }
        }
    }

    func registrationOptions(accountName: String, completion: @escaping (Data?, Data?) -> Void) {
        let url = baseURL.appendingPathComponent("register/\(accountName)")
        let request = URLRequest(url: url)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.handleServerResponse(
                data: data,
                response: response,
                error: error,
                successMessage: "Registration options retrieved successfully",
                failureMessage: "Error fetching registration options",
                completion: { (result: Result<RegistrationOptionsResponse, Error>) in
                    switch result {
                    case let .success(response):
                        let challengeData = Data(base64Encoded: response.publicKey.challenge.base64URLToBase64())
                        let userIDData = Data(base64Encoded: response.publicKey.user.id.base64URLToBase64())
                        completion(challengeData, userIDData)
                    case let .failure(error):
                        print("Failed to get registration options: \(error.localizedDescription)")
                        completion(nil, nil)
                    }
                }
            )
        }.resume()
    }

    func signIn(accountName: String) {
        guard !accountName.isEmpty else {
            print("Account name cannot be empty")
            return
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "webauthn.arkavo.net")

        authenticationOptions(accountName: accountName) { result in
            switch result {
            case let .success(challengeData):
                print("signIn challengeData \(challengeData.base64EncodedString())")
                let assertionRequest = provider.createCredentialAssertionRequest(challenge: challengeData)

                let controller = ASAuthorizationController(authorizationRequests: [assertionRequest])
                controller.delegate = self
                controller.presentationContextProvider = self
                DispatchQueue.main.async {
                    controller.performRequests()
                }
            case let .failure(error):
                print("Failed to get authentication options: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    // Notify the user of the error
                }
            }
        }
    }

    func authenticationOptions(accountName: String, completion: @escaping (Result<Data, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("authenticate/\(accountName)")
        let request = URLRequest(url: url)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.handleServerResponse(
                data: data,
                response: response,
                error: error,
                successMessage: "Authentication options retrieved successfully",
                failureMessage: "Error fetching authentication options",
                completion: { (result: Result<AuthenticationOptionsResponse, Error>) in
                    switch result {
                    case let .success(response):
                        if let challengeData = Data(base64Encoded: response.publicKey.challenge.base64URLToBase64()) {
                            completion(.success(challengeData))
                        } else {
                            completion(.failure(NSError(domain: "ChallengeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to decode challenge string"])))
                        }
                    case let .failure(error):
                        completion(.failure(error))
                    }
                }
            )
        }.resume()
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("Authorization completed successfully")
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            sendRegistrationDataToServer(credential: credential)
        } else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            sendAuthenticationDataToServer(credential: credential)
        }
    }

    private func sendAuthenticationDataToServer(credential: ASAuthorizationPlatformPublicKeyCredentialAssertion) {
        print("sendAuthenticationDataToServer")
        let url = baseURL.appendingPathComponent("authenticate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "id": credential.credentialID.base64URLEncodedString(),
            "rawId": credential.credentialID.base64URLEncodedString(),
            "response": [
                "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                "authenticatorData": credential.rawAuthenticatorData.base64URLEncodedString(),
                "signature": credential.signature.base64URLEncodedString(),
                "userHandle": credential.userID.base64URLEncodedString(),
            ],
            "type": "public-key",
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            // print("Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to print request body")")
        } catch {
            print("Error creating authentication JSON data: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("Error sending authentication data: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                return
            }

            if (200 ... 299).contains(httpResponse.statusCode) {
                print("Authentication successful")
                if let data, !data.isEmpty {
                    // Try to parse the response as JSON if there's data
                    do {
                        if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            print("Parsed JSON response: \(jsonResult)")
                            // Handle any additional server response data here
                        }
                    } catch {
                        print("Failed to parse JSON data. Error: \(error)")
                    }
                } else {
                    print("No data in response body, but authentication was successful")
                }

                DispatchQueue.main.async {
                    // Update UI or app state to reflect successful authentication
                    self.currentAccount = credential.userID.base64EncodedString()
                    // Notify the user of successful authentication
                }
            } else {
                print("Authentication failed with status code: \(httpResponse.statusCode)")
                if let data, let responseString = String(data: data, encoding: .utf8) {
                    print("Server response: \(responseString)")
                }
                DispatchQueue.main.async {
                    // Notify the user of authentication failure
                }
            }
        }.resume()
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
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
        let url = baseURL.appendingPathComponent("register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Decode the clientDataJSON to verify the challenge
        if let clientDataJSONString = String(data: credential.rawClientDataJSON, encoding: .utf8),
           let clientDataJSON = try? JSONSerialization.jsonObject(with: credential.rawClientDataJSON, options: []) as? [String: Any],
           let challenge = clientDataJSON["challenge"] as? String
        {
            print("Client data JSON: \(clientDataJSONString)")
            print("Extracted challenge: \(challenge)")
        }
        let parameters: [String: Any] = [
            "id": credential.credentialID.base64URLEncodedString(),
            "rawId": credential.credentialID.base64URLEncodedString(),
            "response": [
                "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                "attestationObject": credential.rawAttestationObject!.base64URLEncodedString(),
            ],
            "type": "public-key",
            "extensions": [:], // Add any extensions if needed
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            // print("Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to print request body")")
        } catch {
            print("Error creating registration JSON data: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("Error sending registration data: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                return
            }

            guard let data else {
                print("No data received from server")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
            }

            if (200 ... 299).contains(httpResponse.statusCode) {
                // Try to parse the response as JSON
                do {
                    if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        print("Parsed JSON response: \(jsonResult)")
                        // Handle successful registration here
                        DispatchQueue.main.async {
                            self.currentAccount = jsonResult["username"] as? String
                            // Notify the user of successful registration
                        }
                    }
                } catch {
                    // currently empty
                    // print("Failed to parse JSON data. Error: \(error)")
                }
            } else {
                print("Registration failed with status code: \(httpResponse.statusCode)")
                // Handle registration failure
                DispatchQueue.main.async {
                    // Notify the user of registration failure
                }
            }
        }.resume()
    }

    func createJWT() -> String? {
        guard let account = currentAccount else {
            print("No account available to create JWT")
            return nil
        }

        // Create JWT header
        let header = ["alg": "HS256", "typ": "JWT"]

        // Create JWT payload
        let payload: [String: Any] = [
            "sub": account,
            "exp": Int(Date().addingTimeInterval(3600).timeIntervalSince1970),
            "iat": Int(Date().timeIntervalSince1970),
            "iss": "Arkavo App",
            "aud": ["kas.arkavo.net"],
        ]

        // Encode header and payload
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload)
        else {
            print("Failed to encode header or payload")
            return nil
        }

        let headerString = headerData.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let payloadString = payloadData.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // Create signature
        let signatureInput = "\(headerString).\(payloadString)"
        // In a real-world scenario, you'd use a secure way to store and retrieve this key
        let key = SymmetricKey(size: .bits256)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signatureInput.utf8), using: key)
        let signatureString = Data(signature).base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // Combine all parts
        return "\(headerString).\(payloadString).\(signatureString)"
    }

    func updateAccount(_ newAccount: String) {
        currentAccount = newAccount
    }
}

struct AuthenticationOptionsResponse: Decodable {
    let publicKey: PublicKeyAuthenticationOptions
}

struct RegistrationOptionsResponse: Decodable {
    let publicKey: PublicKeyRegistrationOptions
}

struct PublicKeyAuthenticationOptions: Decodable {
    let challenge: String
}

struct PublicKeyRegistrationOptions: Decodable {
    let challenge: String
    let user: User
}

struct User: Decodable {
    let id: String
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    func base64URLToBase64() -> String {
        var base64 = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if base64.count % 4 != 0 {
            base64.append(String(repeating: "=", count: 4 - base64.count % 4))
        }
        return base64
    }
}
