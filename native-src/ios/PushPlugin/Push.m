#import "Push.h"
#import <UIKit/UIKit.h>
#import <UIKit/UIUserNotificationSettings.h>
#import <objc/runtime.h>

const NSString * badgeKey = @"badge";
const NSString * soundKey = @"sound";
const NSString * alertKey = @"alert";
const NSString * areNotificationsEnabledEventName = @"areNotificationsEnabled";
const NSString * didUnregisterEventName = @"didUnregister";
const NSString * didRegisterEventName = @"didRegisterForRemoteNotificationsWithDeviceToken";
const NSString * didFailToRegisterEventName = @"didFailToRegisterForRemoteNotificationsWithError";
const NSString * notificationReceivedEventName = @"notificationReceived";
const NSString * setBadgeNumberEventName = @"setApplicationIconBadgeNumber";
const NSString * didRegisterUserNotificationSettingsEventName = @"didRegisterUserNotificationSettings";
const NSString * failToRegisterUserNotificationSettingsEventName = @"failToRegisterUserNotificationSettings";

NSString *const SubscriptionTopic = @"/topics/global";

static char launchNotificationKey;

@interface Push ()
@property(nonatomic, strong) void (^handler) (NSString *registrationToken, NSError *error);
@property(nonatomic, strong) NSString *gcmSenderID;
@property(nonatomic, strong) NSString *deviceToken;
@property(nonatomic, strong) NSString *registrationToken;
@property(nonatomic, assign) BOOL gcmSandbox;
@property(nonatomic, assign) BOOL subscribedToTopic;
@property(nonatomic, assign) BOOL connectedToGCM;
@end

@implementation Push

@synthesize notificationMessage;
@synthesize isInline;

+ (instancetype)sharedInstance {
    static Push *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Push alloc] init];
    });
    return sharedInstance;
}

- (void)areNotificationsEnabled {
    BOOL registered;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(isRegisteredForRemoteNotifications)]) {
        registered = [[UIApplication sharedApplication] isRegisteredForRemoteNotifications];
    } else {
        UIRemoteNotificationType types = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
        registered = types != UIRemoteNotificationTypeNone;
    }
#else
    UIRemoteNotificationType types = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
    registered = types != UIRemoteNotificationTypeNone;
#endif
    NSString * booleanString = (registered) ? @"true" : @"false";
    [self success:areNotificationsEnabledEventName WithMessage:booleanString];
}

- (void)unregister {
    [[UIApplication sharedApplication] unregisterForRemoteNotifications];
    [self success:didUnregisterEventName WithMessage:@"Success"];
}

-(void)register:(NSMutableDictionary *)options {
    isInline = NO;

    Push *push = [Push sharedInstance];
    push.gcmSenderID = [options objectForKey:@"senderID"];
    push.gcmSandbox  = [self isTrue:@"sandbox" fromOptions:options];
    
    GCMConfig *gcmConfig = [GCMConfig defaultConfig];
    gcmConfig.receiverDelegate = self;
    [[GCMService sharedInstance] startWithConfig:gcmConfig];
    
    push.handler = ^(NSString *registrationToken, NSError *error) {
        if (registrationToken != nil) {
            push.registrationToken = registrationToken;
            [push subscribeToTopic];
            [[NSNotificationCenter defaultCenter]
                 postNotificationName:didRegisterEventName
                 object:self
                 userInfo:@{@"message":registrationToken}];
        } else {
            [[NSNotificationCenter defaultCenter]
                 postNotificationName:didFailToRegisterEventName
                 object:self
                 userInfo:@{@"error":error.localizedDescription}];
        }
    };

    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_7_1) {
        // iOS 7.1 or earlier
        UIRemoteNotificationType notificationTypes = UIRemoteNotificationTypeNone;
        notificationTypes |= UIRemoteNotificationTypeNewsstandContentAvailability;
        
        if([self isTrue: badgeKey fromOptions: options]) notificationTypes |= UIRemoteNotificationTypeBadge;
        if([self isTrue: soundKey fromOptions: options]) notificationTypes |= UIRemoteNotificationTypeSound;
        if([self isTrue: alertKey fromOptions: options]) notificationTypes |= UIRemoteNotificationTypeAlert;

        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:notificationTypes];
    } else {
        // iOS 8 or later
        UIUserNotificationType UserNotificationTypes = UIUserNotificationTypeNone;
        if([self isTrue: badgeKey fromOptions: options]) UserNotificationTypes |= UIUserNotificationTypeBadge;
        if([self isTrue: soundKey fromOptions: options]) UserNotificationTypes |= UIUserNotificationTypeSound;
        if([self isTrue: alertKey fromOptions: options]) UserNotificationTypes |= UIUserNotificationTypeAlert;
        UserNotificationTypes |= UIUserNotificationActivationModeBackground;

        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UserNotificationTypes categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
}

- (void)subscribeToTopic {
    // If the app has a registration token and is connected to GCM, proceed to subscribe to the
    // topic
    if (_registrationToken && _connectedToGCM) {
        [[GCMPubSub sharedInstance] subscribeWithToken:_registrationToken
                                                 topic:SubscriptionTopic
                                               options:nil
                                               handler:^(NSError *error) {
           if (error) {
               // Treat the "already subscribed" error more gently
               if (error.code != 3001) {
                   NSLog(@"Subscription failed: %@", error.localizedDescription);
               }
           } else {
               self.subscribedToTopic = true;
               NSLog(@"Subscribed to %@", SubscriptionTopic);
           }
        }];
    }
}

- (BOOL)isTrue:(NSString *)key fromOptions:(NSMutableDictionary *)options {
    id arg = [options objectForKey:key];
    
    if([arg isKindOfClass:[NSString class]]) return [arg isEqualToString:@"true"];
    if([arg boolValue]) return true;
    
    return false;
}

/**
 *  Called when the system determines that tokens need to be refreshed.
 *  This method is also called if Instance ID has been reset in which
 *  case, tokens and `GcmPubSub` subscriptions also need to be refreshed.
 *
 *  Instance ID service will throttle the refresh event across all devices
 *  to control the rate of token updates on application servers.
 */
- (void)onTokenRefresh {
    Push *push = [Push sharedInstance];

    NSDictionary *registrationOptions = @{kGGLInstanceIDRegisterAPNSOption:push.deviceToken,
                                          kGGLInstanceIDAPNSServerTypeSandboxOption:@(push.gcmSandbox)};
    
    [[GGLInstanceID sharedInstance] tokenWithAuthorizedEntity:push.gcmSenderID
                                                        scope:kGGLInstanceIDScopeGCM
                                                      options:registrationOptions
                                                      handler:push.handler];
}

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    Push *push = [Push sharedInstance];
    push.deviceToken = deviceToken;
    
    // Create a config and set a delegate that implements the GGLInstaceIDDelegate protocol.
    GGLInstanceIDConfig *instanceIDConfig = [GGLInstanceIDConfig defaultConfig];
    instanceIDConfig.delegate = self;

    // Start the GGLInstanceID shared instance with the that config and request a registration
    // token to enable reception of notifications
    [[GGLInstanceID sharedInstance] startWithConfig:instanceIDConfig];
    
    NSDictionary *registrationOptions = @{kGGLInstanceIDRegisterAPNSOption:push.deviceToken,
                                           kGGLInstanceIDAPNSServerTypeSandboxOption:@(push.gcmSandbox)};

    
    [[GGLInstanceID sharedInstance] tokenWithAuthorizedEntity:push.gcmSenderID
                                                        scope:kGGLInstanceIDScopeGCM
                                                      options:registrationOptions
                                                      handler:push.handler];
}

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    [self fail:didFailToRegisterEventName WithMessage:@"" withError:error];
}

- (void)notificationReceived {
    if (self.notificationMessage) {
        
        NSMutableString *jsonStr = [NSMutableString stringWithString:@"{"];
        
        [self parseDictionary:self.notificationMessage intoJSON:jsonStr];
        
        if (isInline) {
            [jsonStr appendFormat:@"\"foreground\":\"%d\"", 1];
            isInline = NO;
        } else {
            [jsonStr appendFormat:@"\"foreground\":\"%d\"", 0];
        }
        
        [jsonStr appendString:@"}"];
        
        [self success:notificationReceivedEventName WithMessage:jsonStr];
        self.notificationMessage = nil;
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Connect to the GCM server to receive non-APNS notifications
    [[GCMService sharedInstance] connectWithHandler:^(NSError *error) {
        Push *push = [Push sharedInstance];
        if (error) {
            NSLog(@"Could not connect to GCM: %@", error.localizedDescription);
        } else {
            push.connectedToGCM = true;
            NSLog(@"Connected to GCM");
            [push subscribeToTopic];
        }
    }];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [[GCMService sharedInstance] disconnect];
    [Push sharedInstance].connectedToGCM = NO;
}

- (void)application:(UIApplication *)application didReceiveMessage:(NSDictionary *)userInfo {
    [[GCMService sharedInstance] appDidReceiveMessage:userInfo];

    UIApplicationState appState = UIApplicationStateActive;
    if ([application respondsToSelector:@selector(applicationState)]) {
        appState = application.applicationState;
    }
    
    Push *push = [Push sharedInstance];
    if (appState == UIApplicationStateActive) {
        push.notificationMessage = userInfo;
        push.isInline = YES;
        [push notificationReceived];
    } else {
        push.launchNotification = userInfo;
    }
}

- (void)parseDictionary:(NSDictionary *)inDictionary intoJSON:(NSMutableString *)jsonString {
    NSArray         *keys = [inDictionary allKeys];
    NSString        *key;
    
    for (key in keys) {
        id thisObject = [inDictionary objectForKey:key];
        
        if ([thisObject isKindOfClass:[NSDictionary class]])
            [self parseDictionary:thisObject intoJSON:jsonString];
        else if ([thisObject isKindOfClass:[NSString class]])
            [jsonString appendFormat:@"\"%@\":\"%@\",",
             key,
             [[[[inDictionary objectForKey:key]
                stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
               stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]
              stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]];
        else {
            [jsonString appendFormat:@"\"%@\":\"%@\",", key, [inDictionary objectForKey:key]];
        }
    }
}

- (void)setApplicationIconBadgeNumber:(NSMutableDictionary *)options {
    int badge = [[options objectForKey:badgeKey] intValue] ?: 0;
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:badge];
    [self success:setBadgeNumberEventName WithMessage:[NSString stringWithFormat:@"app badge count set to %d", badge]];
}

- (void)registerUserNotificationSettings:(NSDictionary*)options {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if (![[UIApplication sharedApplication]respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        [self success:didRegisterUserNotificationSettingsEventName WithMessage:[NSString stringWithFormat:@"%@", @"user notifications not supported for this ios version."]];
        return;
    }
    
    NSArray *categories = [options objectForKey:@"categories"];
    if (categories == nil) {
        [self fail:failToRegisterUserNotificationSettingsEventName WithMessage:@"No categories specified" withError:nil];
        return;
    }
    NSMutableArray *nsCategories = [[NSMutableArray alloc] initWithCapacity:[categories count]];
    
    for (NSDictionary *category in categories) {
        // ** 1. create the actions for this category
        NSMutableArray *nsActionsForDefaultContext = [[NSMutableArray alloc] initWithCapacity:4];
        NSArray *actionsForDefaultContext = [category objectForKey:@"actionsForDefaultContext"];
        if (actionsForDefaultContext == nil) {
            [self fail:failToRegisterUserNotificationSettingsEventName WithMessage:@"Category doesn't contain actionsForDefaultContext" withError:nil];
            return;
        }
        if (![self createNotificationAction:category actions:actionsForDefaultContext nsActions:nsActionsForDefaultContext]) {
            return;
        }
        
        NSMutableArray *nsActionsForMinimalContext = [[NSMutableArray alloc] initWithCapacity:2];
        NSArray *actionsForMinimalContext = [category objectForKey:@"actionsForMinimalContext"];
        if (actionsForMinimalContext == nil) {
            [self fail:failToRegisterUserNotificationSettingsEventName WithMessage:@"Category doesn't contain actionsForMinimalContext" withError:nil];
            return;
        }
        if (![self createNotificationAction:category actions:actionsForMinimalContext nsActions:nsActionsForMinimalContext]) {
            return;
        }
        
        // ** 2. create the category
        UIMutableUserNotificationCategory *nsCategory = [[UIMutableUserNotificationCategory alloc] init];
        // Identifier to include in your push payload and local notification
        NSString *identifier = [category objectForKey:@"identifier"];
        if (identifier == nil) {
            [self fail:failToRegisterUserNotificationSettingsEventName WithMessage:@"Category doesn't contain identifier" withError:nil];
            return;
        }
        nsCategory.identifier = identifier;
        // Add the actions to the category and set the action context
        [nsCategory setActions:nsActionsForDefaultContext forContext:UIUserNotificationActionContextDefault];
        // Set the actions to present in a minimal context
        [nsCategory setActions:nsActionsForMinimalContext forContext:UIUserNotificationActionContextMinimal];
        [nsCategories addObject:nsCategory];
    }
    
    // ** 3. Determine the notification types
    NSArray *types = [options objectForKey:@"types"];
    if (types == nil) {
        [self fail:failToRegisterUserNotificationSettingsEventName WithMessage:@"No types specified" withError:nil];
        return;
    }
    UIUserNotificationType nsTypes = UIUserNotificationTypeNone;
    for (NSString *type in types) {
        if ([type isEqualToString:badgeKey]) {
            nsTypes |= UIUserNotificationTypeBadge;
        } else if ([type isEqualToString:alertKey]) {
            nsTypes |= UIUserNotificationTypeAlert;
        } else if ([type isEqualToString:soundKey]) {
            nsTypes |= UIUserNotificationTypeSound;
        } else {
            [self fail:failToRegisterUserNotificationSettingsEventName WithMessage:[NSString stringWithFormat:@"Unsupported type: %@, use one of badge, alert, sound", type] withError:nil];
        }
    }
    
    // ** 4. Register the notification categories
    NSSet *nsCategorySet = [NSSet setWithArray:nsCategories];
    
    
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:nsTypes categories:nsCategorySet];
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
#endif
    [self success:didRegisterUserNotificationSettingsEventName WithMessage:[NSString stringWithFormat:@"%@", @"user notifications registered"]];
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
- (BOOL)createNotificationAction:(NSDictionary *)category
                         actions:(NSArray *) actions
                       nsActions:(NSMutableArray *)nsActions
{
    for (NSDictionary *action in actions) {
        UIMutableUserNotificationAction *nsAction = [[UIMutableUserNotificationAction alloc] init];
        // Define an ID string to be passed back to your app when you handle the action
        NSString *identifier = [action objectForKey:@"identifier"];
        if (identifier == nil) {
            [self fail:failToRegisterUserNotificationSettingsEventName WithMessage:@"Action doesn't contain identifier" withError:nil];
            return NO;
        }
        nsAction.identifier = identifier;
        // Localized text displayed in the action button
        NSString *title = [action objectForKey:@"title"];
        if (title == nil) {
            [self fail:failToRegisterUserNotificationSettingsEventName WithMessage:@"Action doesn't contain title" withError:nil];
            return NO;
        }
        nsAction.title = title;
        // If you need to show UI, choose foreground (background gives your app a few seconds to run)
        BOOL isForeground = [@"foreground" isEqualToString:[action objectForKey:@"activationMode"]];
        nsAction.activationMode = isForeground ? UIUserNotificationActivationModeForeground : UIUserNotificationActivationModeBackground;
        // Destructive actions display in red
        BOOL isDestructive = [[action objectForKey:@"destructive"] isEqual:[NSNumber numberWithBool:YES]];
        nsAction.destructive = isDestructive;
        // Set whether the action requires the user to authenticate
        BOOL isAuthRequired = [[action objectForKey:@"authenticationRequired"] isEqual:[NSNumber numberWithBool:YES]];
        nsAction.authenticationRequired = isAuthRequired;
        [nsActions addObject:nsAction];
    }
    return YES;
}
#endif

-(void)success:(NSString *)eventName WithDictionary:(NSMutableDictionary *)userInfo
{
    [[NSNotificationCenter defaultCenter]
     postNotificationName:eventName
     object:self userInfo:userInfo];
}

-(void)success:(NSString *)eventName WithMessage:(NSString *)message
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setValue:message forKey:@"message"];
    [[NSNotificationCenter defaultCenter]
     postNotificationName:eventName
     object:self userInfo:userInfo];
}

-(void)fail:(NSString *)eventName WithMessage:(NSString *)message withError:(NSError *)error
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    NSString *errorMessage = (error) ? [NSString stringWithFormat:@"%@ - %@", message, [error localizedDescription]] : message;
    [userInfo setValue:errorMessage forKey:@"message"];
    
    [[NSNotificationCenter defaultCenter]
     postNotificationName:eventName
     object:self userInfo:userInfo];
}

- (NSMutableArray *)launchNotification
{
    return objc_getAssociatedObject(self, &launchNotificationKey);
}

- (void)setLaunchNotification:(NSDictionary *)aDictionary
{
    objc_setAssociatedObject(self, &launchNotificationKey, aDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dealloc
{
    self.launchNotification	= nil;
}

@end
