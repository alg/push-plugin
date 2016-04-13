#import "PushManager.h"
#import <UIKit/UIApplication.h>
#import <objc/runtime.h>
#import "Push.h"

@implementation PushManager
/*__attribute__((constructor))
void myFunction() {
    @autoreleasepool {
        NSLog(@"stuff happened early");
    }
}*/

static IMP didRegisterOriginalMethod = NULL;
static IMP didFailOriginalMethod = NULL;
static IMP didReceiveOriginalMethod = NULL;
static IMP didReceiveFetchOriginalMethod = NULL;
static IMP handleActionWithIdentifierOriginalMethod = NULL;

+ (void)captureDidRegisterForRemoteNotificationsWithDeviceToken {
    UIApplication *app = [UIApplication sharedApplication];
    id<UIApplicationDelegate> appDelegate = app.delegate;

    Method didRegisterMethod = class_getInstanceMethod([PushManager class], @selector(my_application:didRegisterForRemoteNotificationsWithDeviceToken:));
    IMP didRegisterMethodImp = method_getImplementation(didRegisterMethod);
    const char* didRegisterTypes = method_getTypeEncoding(didRegisterMethod);
    
    Method didRegisterOriginal = class_getInstanceMethod(appDelegate.class, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:));
    if (didRegisterOriginal) {
        didRegisterOriginalMethod = method_getImplementation(didRegisterOriginal);
        method_exchangeImplementations(didRegisterOriginal, didRegisterMethod);
    } else {
        class_addMethod(appDelegate.class, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), didRegisterMethodImp, didRegisterTypes);
    }
}

+ (void)captureDidFailToRegisterForRemoteNotificationsWithError {
    UIApplication *app = [UIApplication sharedApplication];
    id<UIApplicationDelegate> appDelegate = app.delegate;
  
    Method didFailMethod = class_getInstanceMethod([PushManager class], @selector(my_application:didFailToRegisterForRemoteNotificationsWithError:));
    IMP didFailMethodImp = method_getImplementation(didFailMethod);
    const char* didFailTypes = method_getTypeEncoding(didFailMethod);
    
    Method didFailOriginal = class_getInstanceMethod(appDelegate.class, @selector(application:didFailToRegisterForRemoteNotificationsWithError:));
    if (didFailOriginal) {
        didFailOriginalMethod = method_getImplementation(didFailOriginal);
        method_exchangeImplementations(didFailOriginal, didFailMethod);
    } else {
        class_addMethod(appDelegate.class, @selector(application:didFailToRegisterForRemoteNotificationsWithError:), didFailMethodImp, didFailTypes);
    }
}

+ (void)captureDidReceiveRemoteNotification {
    UIApplication *app = [UIApplication sharedApplication];
    id<UIApplicationDelegate> appDelegate = app.delegate;
  
    Method didReceiveMethod = class_getInstanceMethod([PushManager class], @selector(my_application:didReceiveRemoteNotification:));
    IMP didReceiveMethodImp = method_getImplementation(didReceiveMethod);
    const char* didReceiveTypes = method_getTypeEncoding(didReceiveMethod);
    
    Method didReceiveOriginal = class_getInstanceMethod(appDelegate.class, @selector(application:didReceiveRemoteNotification:));
    if (didReceiveOriginal) {
        didReceiveOriginalMethod = method_getImplementation(didReceiveOriginal);
        method_exchangeImplementations(didReceiveOriginal, didReceiveMethod);
    } else {
        class_addMethod(appDelegate.class, @selector(application:didReceiveRemoteNotification:), didReceiveMethodImp, didReceiveTypes);
    }
}

+ (void)captureDidReceiveRemoteNotificationFetchCompletionHandler {
    UIApplication *app = [UIApplication sharedApplication];
    id<UIApplicationDelegate> appDelegate = app.delegate;
  
    Method didReceiveFetchMethod = class_getInstanceMethod([PushManager class], @selector(my_application:didReceiveRemoteNotification:fetchCompletionHandler:));
    IMP didReceiveFetchMethodImp = method_getImplementation(didReceiveFetchMethod);
    const char* didReceiveFetchTypes = method_getTypeEncoding(didReceiveFetchMethod);
    
    Method didReceiveFetchOriginal = class_getInstanceMethod(appDelegate.class, @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:));
    if (didReceiveFetchOriginal) {
        didReceiveFetchOriginalMethod = method_getImplementation(didReceiveFetchOriginal);
        method_exchangeImplementations(didReceiveFetchOriginal, didReceiveFetchMethod);
    } else {
        class_addMethod(appDelegate.class, @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:), didReceiveFetchMethodImp, didReceiveFetchTypes);
    }
}

+ (void)captureHandleActionWithIdentifier {
    UIApplication *app = [UIApplication sharedApplication];
    id<UIApplicationDelegate> appDelegate = app.delegate;
    
    Method handleActionWithIdentifierMethod = class_getInstanceMethod([PushManager class], @selector(my_application:handleActionWithIdentifier:forRemoteNotification:completionHandler:));
    IMP handleActionWithIdentifierMethodImp = method_getImplementation(handleActionWithIdentifierMethod);
    const char* handleActionWithIdentifierTypes = method_getTypeEncoding(handleActionWithIdentifierMethod);
    
    Method handleActionWithIdentifierOriginal = class_getInstanceMethod(appDelegate.class, @selector(application:handleActionWithIdentifier:forRemoteNotification:completionHandler:));
    if (handleActionWithIdentifierOriginal) {
        handleActionWithIdentifierOriginalMethod = method_getImplementation(handleActionWithIdentifierOriginal);
        method_exchangeImplementations(handleActionWithIdentifierOriginal, handleActionWithIdentifierMethod);
    } else {
        class_addMethod(appDelegate.class, @selector(application:handleActionWithIdentifier:forRemoteNotification:completionHandler:), handleActionWithIdentifierMethodImp, handleActionWithIdentifierTypes);
    }
}

+ (void)load {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        
        [PushManager captureDidRegisterForRemoteNotificationsWithDeviceToken];
        [PushManager captureDidFailToRegisterForRemoteNotificationsWithError];
        [PushManager captureDidReceiveRemoteNotification];
        [PushManager captureDidReceiveRemoteNotificationFetchCompletionHandler];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(my_applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(my_applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        
        #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
        [PushManager captureHandleActionWithIdentifier];
        #endif
    }];
    
}

-(id)init {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createNotificationChecker:)
                                                 name:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    return self;
}

- (void)createNotificationChecker:(NSNotification *)notification {
    if (notification) {
        NSDictionary *launchOptions = [notification userInfo];
        if (launchOptions) {
            [Push sharedInstance].launchNotification = [launchOptions objectForKey: @"UIApplicationLaunchOptionsRemoteNotificationKey"];
        }
    }
}

+ (void)my_applicationDidBecomeActive:(NSNotification *)notification {
    
    UIApplication *application = [UIApplication sharedApplication];
    
    application.applicationIconBadgeNumber = 0;
    
    // Call Push so that it subscribes to GCMService
    [[Push sharedInstance] applicationDidBecomeActive:application];
    
    if ([Push sharedInstance].launchNotification) {
        [Push sharedInstance].notificationMessage  = [Push sharedInstance].launchNotification;
        [Push sharedInstance].launchNotification = nil;
        [[Push sharedInstance] performSelectorOnMainThread:@selector(notificationReceived) withObject:[Push sharedInstance]  waitUntilDone:NO];
    }
}

// Call Push so that it unsubscribes from GCMService
+ (void)my_applicationDidEnterBackground:(NSNotification *)notification {
    UIApplication *application = [UIApplication sharedApplication];
    [[Push sharedInstance] applicationDidEnterBackground:application];
}

- (void)my_application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
   if (didRegisterOriginalMethod) {
        void (*originalImp)(id, SEL, UIApplication *, NSData *) = didRegisterOriginalMethod;
        originalImp(self, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), application, deviceToken);
    }
    NSLog(@"%@", deviceToken);
    [[Push sharedInstance] didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)my_application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    if (didReceiveOriginalMethod) {
        void (*originalImp)(id, SEL, UIApplication *, NSDictionary *) = didReceiveOriginalMethod;
        originalImp(self, @selector(application:didReceiveRemoteNotification:), application, userInfo);
    }

    [[Push sharedInstance] application:application didReceiveMessage:userInfo];
}

- (void)my_application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler {
    
    if (didReceiveFetchOriginalMethod) {
        void (*originalImp)(id, SEL, UIApplication *, NSDictionary *, void (^)(UIBackgroundFetchResult)) = didReceiveFetchOriginalMethod;
        originalImp(self, @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:), application, userInfo, handler);
    }

    [[Push sharedInstance] application:application didReceiveMessage:userInfo];
    
    // call completion handler with no data received result
    handler(UIBackgroundFetchResultNoData);
}

- (void)my_application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    if (didFailOriginalMethod) {
        void (*originalImp)(id, SEL, UIApplication *, NSError *) = didFailOriginalMethod;
        originalImp(self, @selector(application:didFailToRegisterForRemoteNotificationsWithError:), application, error);
    }
    NSLog(@"Error registering...");
    [[Push sharedInstance] didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void)my_application:(UIApplication *) application handleActionWithIdentifier: (NSString *) identifier forRemoteNotification: (NSDictionary *) notification completionHandler: (void (^)()) completionHandler {
    
    NSLog(@"handle action with identifier");
    
    NSMutableDictionary *mutableNotification = [notification mutableCopy];
    
    [mutableNotification setObject:identifier forKey:@"identifier"];
    if (application.applicationState == UIApplicationStateActive) {
        [Push sharedInstance].notificationMessage = mutableNotification;
        [Push sharedInstance].isInline = YES;
        [[Push sharedInstance] notificationReceived];
    } else {
        [Push sharedInstance].notificationMessage = mutableNotification;
        [[Push sharedInstance] performSelectorOnMainThread:@selector(notificationReceived) withObject:[Push sharedInstance] waitUntilDone:NO];
    }
    
    if (handleActionWithIdentifierOriginalMethod) {
        void (*originalImp)(id, SEL, UIApplication *, NSString *, NSDictionary *, void(^)()) = handleActionWithIdentifierOriginalMethod;
        originalImp(self, @selector(application:handleActionWithIdentifier:forRemoteNotification:completionHandler:), application, identifier, notification, completionHandler);
    } else {
        completionHandler();
    }
}


@end
