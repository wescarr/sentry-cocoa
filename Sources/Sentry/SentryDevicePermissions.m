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
#import <UserNotifications/UserNotifications.h>

#if SENTRY_HAS_UIKIT
#import <UIKit/UIKit.h>
#endif

@interface SentryDevicePermissions () <CLLocationManagerDelegate>
@end

@implementation SentryDevicePermissions {
    CLLocationManager *locationManager;
    NSMutableDictionary<NSString *, NSNumber *> * permissionCache;
    UNUserNotificationCenter *pushCenter;
}

- (instancetype)init {
    if (self = [super init]) {
        [self initialize];
    }
    return self;
}

- (void)initialize {
    permissionCache = [NSMutableDictionary new];
    
    locationManager = [[CLLocationManager alloc] init];
    locationManager.delegate = self;

    pushCenter = [UNUserNotificationCenter currentNotificationCenter];
    [pushCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * settings) {
        if (settings.authorizationStatus == PHAuthorizationStatusNotDetermined) {
            self->permissionCache[@"remote_notification"] = nil;
        } else {
            self->permissionCache[@"remote_notification"] = [NSNumber numberWithBool:settings.authorizationStatus > PHAuthorizationStatusDenied];
        }
    }];
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status{
    if (status == kCLAuthorizationStatusNotDetermined) {
        permissionCache[@"location_service"] = nil;
    } else {
        permissionCache[@"location_service"] = [NSNumber numberWithBool:status > kCLAuthorizationStatusDenied];
    }
}

- (NSDictionary<NSString* , NSNumber *> *)allPermissions {
    //We dont have siri permission because it needs an entitlement.
    //We dont have health permissions because it requires parameters for each type of health information.
    
    void (^checkPermission)(NSString *, NSInteger) = ^void(NSString * name, NSInteger current) {
        //Current value of 0 means not determined, 1 means permission restricted by the system, maybe because of parental control, 2 means denied.
        if (current != 0) {
            [self setPermission:current > 2 forKey:name];
        }
    };
    
    checkPermission(@"location",CLLocationManager.authorizationStatus);
    
    if (@available(iOS 13.1,macOS 10.15, *)) {
        checkPermission(@"bluetooth",CBManager.authorization);
    }
    
    checkPermission(@"microphone",[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]);
    
    checkPermission(@"camera",[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]);
    
    checkPermission(@"contacts",[CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts]);
    
    checkPermission(@"calendar",[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent]);
    
    checkPermission(@"media_library",MPMediaLibrary.authorizationStatus);
    
    if (@available(iOS 11.0, *)) {
        checkPermission(@"motion",CMMotionActivityManager.authorizationStatus);
    }
    
    checkPermission(@"photo_library",PHPhotoLibrary.authorizationStatus);
    
    checkPermission(@"speech",SFSpeechRecognizer.authorizationStatus);
    
    if (@available(iOS 14, *)) {
        checkPermission(@"tracking",ATTrackingManager.trackingAuthorizationStatus);
    }
    return permissionCache;
}

-(void)setPermission:(BOOL)permission forKey:(NSString*)key{
    permissionCache[key] = [NSNumber numberWithBool:permission];
}

@end
