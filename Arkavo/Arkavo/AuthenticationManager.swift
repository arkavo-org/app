import AuthenticationServices
import CryptoKit
import Foundation
import SwiftData

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

// TODO: rename to AuthenticationService
class AuthenticationManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let signingKeyAppTag: String = "net.arkavo.Arkavo"
    private let relyingPartyIdentifier: String = "webauthn.arkavo.net"
    private let baseURL = URL(string: "https://webauthn.arkavo.net")!
    private var authenticationToken: Data?

    override init() {}

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
//        print("presentationAnchor called")

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
//            print("signUp challengeData \(challengeData)")
            let publicKeyCredentialRequest = provider.createCredentialRegistrationRequest(
                challenge: challengeData,
                name: accountName,
                userID: userIDData
            )
            let controller = ASAuthorizationController(authorizationRequests: [publicKeyCredentialRequest])
            controller.delegate = self
            controller.presentationContextProvider = self
            DispatchQueue.main.async {
                controller.performRequests(options: .preferImmediatelyAvailableCredentials)
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

    func signIn(accountName: String, authenticationToken: String) async {
        guard !accountName.isEmpty else {
            print("Account name cannot be empty")
            return
        }
//         debug only
//        inspectKeychain()
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)

        authenticationOptions(accountName: accountName, authenticationToken: authenticationToken) { result in
            switch result {
            case let .success(challengeData):
                print("signIn challengeData \(challengeData.base64EncodedString())")
                let assertionRequest = provider.createCredentialAssertionRequest(challenge: challengeData)

                let controller = ASAuthorizationController(authorizationRequests: [assertionRequest])
                controller.delegate = self
                controller.presentationContextProvider = self
                DispatchQueue.main.async {
                    controller.performRequests(options: .preferImmediatelyAvailableCredentials)
                }
            case let .failure(error):
                print("Failed to get authentication options: \(error.localizedDescription)")
                // FIXME: major issue - user is lost from the backend
//                DispatchQueue.main.async {
//                    // Notify the user of the error
//                }
            }
        }
    }

    func authenticationOptions(accountName: String, authenticationToken: String, completion: @escaping (Result<Data, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("authenticate/\(accountName)")
        var request = URLRequest(url: url)
        // Add X-Auth-Token header
        request.addValue(authenticationToken, forHTTPHeaderField: "X-Auth-Token")
//        print("Request URL: \(request.url?.absoluteString ?? "")")
//        print("Request Method: \(request.httpMethod ?? "")")
//        print("Request Headers:")
//        if let headers = request.allHTTPHeaderFields {
//            for (key, value) in headers {
//                print("  \(key): \(value)")
//            }
//        }
//        if let body = request.httpBody {
//            print("Request Body: \(String(data: body, encoding: .utf8) ?? "")")
//        }
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
//                        print("Failure occurred. Printing detailed response information:")
//
//                        if let httpResponse = response as? HTTPURLResponse {
//                            print("HTTP Status Code: \(httpResponse.statusCode)")
//                            print("Response Headers:")
//                            for (key, value) in httpResponse.allHeaderFields {
//                                print("  \(key): \(value)")
//                            }
//                        }
//
//                        if let responseData = data {
//                            if let responseString = String(data: responseData, encoding: .utf8) {
//                                print("Response Body:")
//                                print(responseString)
//                            } else {
//                                print("Response Body: Unable to decode as UTF-8 string")
//                                print("Raw Data: \(responseData)")
//                            }
//                        } else {
//                            print("Response Body: No data received")
//                        }
//
//                        print("Error: \(error.localizedDescription)")
//                        if let errorResponse = error as NSError? {
//                            print("Error Domain: \(errorResponse.domain)")
//                            print("Error Code: \(errorResponse.code)")
//                            if let errorInfo = errorResponse.userInfo as? [String: Any] {
//                                print("Error User Info:")
//                                for (key, value) in errorInfo {
//                                    print("  \(key): \(value)")
//                                }
//                            }
//                        }
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
//        print("sendAuthenticationDataToServer")
        let url = baseURL.appendingPathComponent("authenticate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
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
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            print("Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to print request body")")
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

//                DispatchQueue.main.async {
//                    // FIXME Update UI or app state to reflect successful authentication
//                    // Notify the user of successful authentication
//                }
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
        // signing key
        // Create and store the EC signing key
        guard let signingKey = createAndStoreECSigningKey() else {
            print("Failed to create signing key")
            return
        }
        // Extract the public key from the signing key
        guard let publicKey = SecKeyCopyPublicKey(signingKey) else {
            print("Failed to get public key from signing key")
            return
        }
        // Convert public key to raw data
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            print("Error getting public key data: \(error!.takeRetainedValue() as Error)")
            return
        }
        let parameters: [String: Any] = [
            "id": credential.credentialID.base64URLEncodedString(),
            "rawId": credential.credentialID.base64URLEncodedString(),
            "response": [
                "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                "attestationObject": credential.rawAttestationObject!.base64URLEncodedString(),
            ],
            "type": "public-key",
            "extensions": [
                "signingPublicKey": publicKeyData.base64URLEncodedString(),
            ],
            // FIXME: move client session signingPublicKey to /authenticate
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            // print("Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to print request body")")
        } catch {
            print("Error creating registration JSON data: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                print("Error sending registration data: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
            }

            if (200 ... 299).contains(httpResponse.statusCode) {
                let authenticationToken = httpResponse.allHeaderFields["x-auth-token"] as? String
                if authenticationToken == nil {
                    print("No authentication token received")
                    return
                }
                // update Account
                Task.detached { @PersistenceActor in
                    do {
                        let account = try await PersistenceController.shared.getOrCreateAccount()
                        account.authenticationToken = authenticationToken
                        try await PersistenceController.shared.saveChanges()
                        print("Saved authentication token")
                    } catch {
                        print("Error: \(error)")
                    }
                }
            } else {
                print("Registration failed with status code: \(httpResponse.statusCode)")
                // TODO: Notify the user of registration failure
//                DispatchQueue.main.async {
//                }
            }
        }.resume()
    }

    func createJWT(profileName: String) -> String? {
        // Create JWT header
        let header = ["alg": "HS256", "typ": "JWT"]

        // Create JWT payload
        let payload: [String: Any] = [
            "sub": profileName,
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

    private func storeAccountInKeychain(accountName: String, account _: String) {
        let account = accountName.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: account,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            print("Account information stored in keychain")
        } else {
            print("Failed to store account information in keychain")
        }
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

import Security

extension AuthenticationManager {
    func createAndStoreECSigningKey() -> SecKey? {
        let accessControl = SecAccessControlCreateWithFlags(nil,
                                                            kSecAttrAccessibleWhenUnlocked,
                                                            [],
                                                            nil)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecUseDataProtectionKeychain as String: true,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: signingKeyAppTag,
                kSecAttrLabel as String: "Arkavo Signing Key",
                kSecAttrCanSign as String: true,
                kSecAttrAccessControl as String: accessControl!,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            print("Error generating private key: \(error!.takeRetainedValue() as Error)")
            return nil
        }

        print("EC signing key created successfully")
        return privateKey
    }

    func getStoredSigningKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: signingKeyAppTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            return (item as! SecKey)
        } else {
            print("Failed to retrieve signing key from keychain. Status: \(status)")
            return nil
        }
    }

    func signData(_ data: Data, with key: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key,
                                                    .ecdsaSignatureMessageX962SHA256,
                                                    data as CFData,
                                                    &error) as Data?
        else {
            print("Error creating signature: \(error!.takeRetainedValue() as Error)")
            return nil
        }
        return signature
    }

    // Debug only
    func inspectKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: signingKeyAppTag,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            if let items = result as? [[String: Any]] {
                for (index, item) in items.enumerated() {
                    print("Key \(index + 1):")
                    if let tag = item[kSecAttrApplicationTag as String] as? Data,
                       let tagString = String(data: tag, encoding: .utf8)
                    {
                        print("  Application Tag: \(tagString)")
                    }
                    if let label = item[kSecAttrLabel as String] as? String {
                        print("  Label: \(label)")
                    }
                    print("  All Attributes: \(item)")
                    print("--------------------")
                }
            }
        } else {
            print("Error querying keychain: \(status)")
        }
    }
}
