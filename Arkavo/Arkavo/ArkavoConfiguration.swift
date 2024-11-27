import Foundation

enum ArkavoConfiguration {
    #if DEBUG
        static let patreonClientId: String = {
            guard let value = ProcessInfo.processInfo.environment["PATREON_CLIENT_ID"] else {
                fatalError("""
                    
                    🚨 PATREON_CLIENT_ID environment variable not set
                    
                    To fix this:
                    1. Go to Xcode -> Your Scheme -> Edit Scheme...
                    2. Select "Run" on the left
                    3. Select "Arguments" tab
                    4. Under "Environment Variables", click "+"
                    5. Add PATREON_CLIENT_ID with your development client ID
                    
                    If you don't have a client ID, get one from the Patreon developer portal.
                    """)
            }
            return value
        }()
        
        static let patreonClientSecret: String = {
            guard let value = ProcessInfo.processInfo.environment["PATREON_CLIENT_SECRET"] else {
                fatalError("""
                    
                    🚨 PATREON_CLIENT_SECRET environment variable not set
                    
                    To fix this:
                    1. Go to Xcode -> Your Scheme -> Edit Scheme...
                    2. Select "Run" on the left
                    3. Select "Arguments" tab
                    4. Under "Environment Variables", click "+"
                    5. Add PATREON_CLIENT_SECRET with your development client secret
                    
                    If you don't have a client secret, get one from the Patreon developer portal.
                    """)
            }
            return value
        }()
    #else
        // Values injected at build time via -D compiler flags for release builds
        static let patreonClientId = PATREON_CLIENT_ID
        static let patreonClientSecret = PATREON_CLIENT_SECRET
    #endif
}
