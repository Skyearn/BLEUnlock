#import "AppDelegate.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSString *id = [[NSBundle mainBundle] bundleIdentifier];
    NSString *mainId = [id stringByReplacingOccurrencesOfString:@".Launcher" withString:@""];
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:mainId].count > 0) {
        [NSApp terminate:self];
        return;
    }

    // Launcher.app -> LoginItems -> Library -> Contents -> BLEUnlock.app
    NSURL *launcherBundleURL = [[NSBundle mainBundle] bundleURL];
    NSURL *mainBundleURL = [[[[launcherBundleURL URLByDeletingLastPathComponent]
                              URLByDeletingLastPathComponent]
                             URLByDeletingLastPathComponent]
                            URLByDeletingLastPathComponent];
    if (mainBundleURL == nil ||
        ![[mainBundleURL pathExtension] isEqualToString:@"app"] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:mainBundleURL.path]) {
        NSLog(@"Failed to locate main app bundle from launcher path: %@", launcherBundleURL.path);
        [NSApp terminate:self];
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:mainBundleURL];
    [NSApp terminate:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
}

@end
