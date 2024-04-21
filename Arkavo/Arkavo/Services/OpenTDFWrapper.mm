#include <vector>
#include <string>
#import <Foundation/Foundation.h>

#include "tdf_client.h"
#include "OpenTDFWrapper.h"

const std::string kas_domain = "https://platform.virtru.us/api/kas"; // https://arkavo.net/kas
const std::string oidc_endpoint = "https://platform.virtru.us";
const std::string client_id = "tdf-client";
const std::string client_secret="123-456";
const std::string organization_name = "tdf";
const std::string client_key_file = "clientKeyFileName";
const std::string client_cert_file = "clientCertFileName";
const std::string cert_authority = "CertAuthority";

@implementation OpenTDFWrapper : NSObject
- (void)client {
    virtru::OIDCCredentials oidcCreds;
    oidcCreds.setClientCredentialsClientSecret(client_id, client_secret, organization_name, oidc_endpoint);
    // Test KAS endpoint - curl https://arkavo.net/kas/v2/kas_public_key
    auto client = virtru::TDFClient(oidcCreds, kas_domain);
    client.enableConsoleLogging();
    // create TDF
    virtru::TDFStorageType tdfStorageType;
    tdfStorageType.setTDFStorageStringType("Hello world");
    auto mytdf = client.encryptData(tdfStorageType);
    // test TDF
    std::vector<std::string> testVector;
    testVector.push_back("isTDF");
    bool isTDF = client.isDataTDF(mytdf);
    testVector.push_back( isTDF ? "true" : "false" );
    for (const std::string& word : testVector) {
        NSLog(@"%s", word.c_str());
    }
}
@end
