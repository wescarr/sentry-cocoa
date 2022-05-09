#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SentryPermission : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic) BOOL granted;

-(instancetype)initWithName:(NSString *)name granted:(BOOL)granted;

@end


@interface SentryDevicePermissions : NSObject


- (NSArray<SentryPermission *> *)allPermissions;


@end

NS_ASSUME_NONNULL_END
