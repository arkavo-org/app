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
//    client.enableConsoleLogging();
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

- (NSData *)encrypt:(NSString *)input {
    NSLog(@"%s", "encrypt");
    virtru::OIDCCredentials oidcCreds;
    oidcCreds.setClientCredentialsClientSecret(client_id, client_secret, organization_name, oidc_endpoint);
    // Test KAS endpoint - curl https://arkavo.net/kas/v2/kas_public_key
    auto client = virtru::TDFClient(oidcCreds, kas_domain);
//    client.enableConsoleLogging();
    // create TDF
    virtru::TDFStorageType tdfStorageType;
    std::string cppString = std::string([input UTF8String]);
    tdfStorageType.setTDFStorageStringType(cppString);
    auto mytdf = client.encryptData(tdfStorageType);
    return [[NSData alloc] initWithBytes:mytdf.data() length:mytdf.size()];
}

- (NSString *)decrypt:(NSData *)input {
    NSLog(@"%s", "decrypt");
    virtru::OIDCCredentials oidcCreds;
    oidcCreds.setClientCredentialsClientSecret(client_id, client_secret, organization_name, oidc_endpoint);
    // Test KAS endpoint - curl https://arkavo.net/kas/v2/kas_public_key
    auto client = virtru::TDFClient(oidcCreds, kas_domain);
//    client.enableConsoleLogging();
    // decrypt TDF
    virtru::TDFStorageType tdfStorageType;
    NSUInteger length = [input length];
    std::vector<virtru::VBYTE> buffer(length);
    memcpy(&buffer[0], [input bytes], length);
    tdfStorageType.setTDFStorageBufferType(buffer);
    auto vectorData = client.decryptData(tdfStorageType);
    // Convert std::vector<VBYTE> to NSData
    NSData *data = [NSData dataWithBytes:vectorData.data() length:vectorData.size()];
    // Convert NSData to NSString
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
