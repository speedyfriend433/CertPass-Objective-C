#import "ViewController.h"
#import <Security/Security.h>

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    [self openDocumentPicker];
}

- (void)openDocumentPicker {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        NSLog(@"No file selected.");
        return;
    }
    
    NSLog(@"Selected p12 file: %@", url);
    
    BOOL success = [self authenticateWithP12File:url];
    if (success) {
        NSLog(@"Authentication successful.");
    } else {
        NSLog(@"Authentication failed.");
    }
}

- (BOOL)authenticateWithP12File:(NSURL *)p12FileURL {
    NSData *p12Data = [NSData dataWithContentsOfURL:p12FileURL];
    if (!p12Data) {
        NSLog(@"Failed to read p12 file.");
        return NO;
    }
    
    CFArrayRef items = NULL;
    NSDictionary *options = @{ (__bridge id)kSecImportExportPassphrase: @"" };
    OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);
    
    if (status != errSecSuccess) {
        NSLog(@"Failed to import PKCS12 data.");
        return NO;
    }
    
    CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
    SecIdentityRef identity = (SecIdentityRef)CFDictionaryGetValue(identityDict, kSecImportItemIdentity);
    
    if (!identity) {
        NSLog(@"Failed to get identity from PKCS12 data.");
        return NO;
    }
    
    SecCertificateRef certificate = NULL;
    status = SecIdentityCopyCertificate(identity, &certificate);
    if (status != errSecSuccess) {
        NSLog(@"Failed to copy certificate from identity.");
        return NO;
    }
    
    NSString *dataToSign = @"This is a test message.";
    NSData *signedData = [self signData:[dataToSign dataUsingEncoding:NSUTF8StringEncoding] withIdentity:identity];
    if (signedData) {
        BOOL isVerified = [self verifySignature:signedData originalData:[dataToSign dataUsingEncoding:NSUTF8StringEncoding] withCertificate:certificate];
        return isVerified;
    } else {
        NSLog(@"Failed to sign data.");
        return NO;
    }
}

- (NSData *)signData:(NSData *)data withIdentity:(SecIdentityRef)identity {
    SecKeyRef privateKey = NULL;
    OSStatus status = SecIdentityCopyPrivateKey(identity, &privateKey);
    if (status != errSecSuccess || !privateKey) {
        NSLog(@"Failed to copy private key from identity.");
        return nil;
    }
    
    CFErrorRef error = NULL;
    NSData *signedData = (NSData *)CFBridgingRelease(SecKeyCreateSignature(privateKey, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256, (__bridge CFDataRef)data, &error));
    
    if (error) {
        NSLog(@"Error signing data: %@", error);
        CFRelease(error);
        return nil;
    }
    
    return signedData;
}

- (BOOL)verifySignature:(NSData *)signature originalData:(NSData *)originalData withCertificate:(SecCertificateRef)certificate {
    SecKeyRef publicKey = SecCertificateCopyKey(certificate);
    if (!publicKey) {
        NSLog(@"Failed to copy public key from certificate.");
        return NO;
    }
    
    CFErrorRef error = NULL;
    BOOL isVerified = SecKeyVerifySignature(publicKey, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256, (__bridge CFDataRef)originalData, (__bridge CFDataRef)signature, &error);
    
    if (error) {
        NSLog(@"Error verifying signature: %@", error);
        CFRelease(error);
    }
    
    return isVerified;
}

@end
