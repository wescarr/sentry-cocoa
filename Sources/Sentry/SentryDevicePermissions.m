#import "SentryDevicePermissions.h"
#import "SentryDefines.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <AVFoundation/AVFoundation.h>
#import <Contacts/Contacts.h>
#import <EventKit/EventKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CoreMotion/CoreMotion.h>
#import <Photos/Photos.h>
#import <Intents/Intents.h>
#import <Speech/Speech.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>

#if SENTRY_HAS_UIKIT
#import <UIKit/UIKit.h>
#endif

@implementation SentryPermission


-(instancetype)initWithName:(NSString *)name granted:(BOOL)granted {
    if (self = [super init]){
        self.name = name;
        self.granted = granted;
    }
    return self;
}

@end

@implementation SentryDevicePermissions


- (NSArray<SentryPermission *> *)allPermissions {
    //We dont have siri permission because it needs an entitlement.
    //We dont have health permissions because it requires parameters for each type of health information.
    
    __block NSMutableArray<SentryPermission *> * result = [NSMutableArray new];
    
    void (^checkPermission)(NSString *, NSInteger, NSInteger) = ^void(NSString * name, NSInteger current, NSInteger deniedValue) {
        //0 means not determined for every authorization status
        if (current != 0) {
            [result addObject:[[SentryPermission alloc] initWithName:name granted:current != deniedValue]];
        }
    };

    checkPermission(@"location_service",CLLocationManager.authorizationStatus,kCLAuthorizationStatusDenied);
    
    if (@available(iOS 13.1, *)) {
        checkPermission(@"bluetooth",CBManager.authorization,CBManagerAuthorizationDenied);
    }
    
    checkPermission(@"microphone",[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio],AVAuthorizationStatusDenied);
    
    checkPermission(@"camera",[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo],AVAuthorizationStatusDenied);
    
#if SENTRY_HAS_UIKIT
    if ([UIApplication respondsToSelector:@selector(sharedApplication)]) {
        UIApplication * app = [UIApplication performSelector:@selector(sharedApplication)];
        if ([app respondsToSelector:@selector(currentUserNotificationSettings)]) {
            UIUserNotificationSettings * notificationSettings = [app performSelector:@selector(currentUserNotificationSettings)];
            [result addObject:[[SentryPermission alloc] initWithName:@"remote_notification" granted:notificationSettings.types != UIUserNotificationTypeNone]];
        }
    }
#endif
    
    checkPermission(@"contacts",[CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts],CNAuthorizationStatusDenied);
    
    checkPermission(@"calendar",[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent],EKAuthorizationStatusDenied);
    
    checkPermission(@"media_library",MPMediaLibrary.authorizationStatus,MPMediaLibraryAuthorizationStatusDenied);
    
    if (@available(iOS 11.0, *)) {
        checkPermission(@"motion",CMMotionActivityManager.authorizationStatus, MPMediaLibraryAuthorizationStatusDenied);
    }
    
    checkPermission(@"photo_library",PHPhotoLibrary.authorizationStatus,PHAuthorizationStatusDenied);
    
    //Siri need an entitlement
    //checkPermission(@"siri",INPreferences.siriAuthorizationStatus,INSiriAuthorizationStatusDenied);
    
    checkPermission(@"speech",SFSpeechRecognizer.authorizationStatus,SFSpeechRecognizerAuthorizationStatusDenied);
    
    if (@available(iOS 14, *)) {
        checkPermission(@"tracking",ATTrackingManager.trackingAuthorizationStatus, SFSpeechRecognizerAuthorizationStatusDenied);
    }
    return result;
}

@end
