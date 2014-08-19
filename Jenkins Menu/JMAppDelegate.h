/**
 * Jenkins Menu
 * https://github.com/qvacua/jenkins-menu
 * http://qvacua.com
 *
 * See LICENSE
 */

#import <Cocoa/Cocoa.h>
#import <Growl/Growl.h>
#import "JMJenkinsDelegate.h"
#import "JMJenkins.h"

@class JMTrustedHostManager;
@class JMKeychainManager;

static NSString *const qUserDefaultsUrlKey = @"jenkinsUrl";
static NSString *const qUserDefaultsIntervalKey = @"interval";
static NSString *const qUserDefaultsSecuredKey = @"fds";    // ups...
static NSString *const qUserDefaultsBlacklistItemsKey = @"blacklistItems";
static NSString *const qUserDefaultsBlacklistItemsFilterKey = @"blacklistItemsFilter";
static NSString *const qUserDefaultsShowDisabledJobs = @"showDisabledJobs";
static const NSInteger qBlacklistItemAddSegment = 0;
static const NSInteger qBlacklistItemRemoveSegment = 1;

@interface JMAppDelegate : NSObject <NSApplicationDelegate, NSUserInterfaceValidations, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxCellDataSource, GrowlApplicationBridgeDelegate, JMJenkinsDelegate>

@property (weak) IBOutlet NSMenu *menu;
@property (weak) IBOutlet NSMenuItem *jobsMenuItem;
@property (weak) IBOutlet NSMenuItem *statusMenuItem;

@property (unsafe_unretained) IBOutlet NSWindow *preferencesWindow;
@property (weak) IBOutlet NSTextField *urlTextField;
@property (weak) IBOutlet NSTextField *intervalTextField;

@property (unsafe_unretained) IBOutlet NSWindow *credentialsWindow;
@property (weak) IBOutlet NSTextField *userTextField;
@property (weak) IBOutlet NSSecureTextField *passwordTextField;
@property (weak) IBOutlet NSButton *storeInKeychanCheckbox;

@property NSMutableArray *tempBlacklistItems;
@property JMJenkinsJobFilter blacklistItemsFilter;
@property (unsafe_unretained) IBOutlet NSWindow *blacklistWindow;
@property (weak) IBOutlet NSTableView *blacklistTableView;
@property (weak) IBOutlet NSSegmentedControl *blacklistItemSegmentedControl;
@property (weak) IBOutlet NSTextField *includeExcludeLabel;

@property BOOL showDisabledJobs;

@property NSStatusItem *statusItem;
@property NSTimer *timer;
@property NSUserDefaults *userDefaults;
@property JMKeychainManager *keychainManager;

@property JMTrustedHostManager *trustedHostManager;
@property JMJenkins *jenkins;
@property NSURL *jenkinsUrl;
@property NSURL *jenkinsXmlUrl;
@property NSTimeInterval interval;

- (IBAction)updateNowAction:(id)sender;
- (IBAction)openJenkinsUrlAction:(id)sender;
- (IBAction)openPreferencesWindowAction:(id)sender;
- (IBAction)setPreferencesAction:(id)sender;

- (IBAction)manageBlacklistAction:(id)sender;
- (IBAction)blacklistItemAction:(id)sender;
- (IBAction)blacklistOkAction:(id)sender;
- (IBAction)blacklistCancelAction:(id)sender;

- (IBAction)credentialsOkAction:(id)sender;
- (IBAction)credentialsCancelAction:(id)sender;
- (IBAction)storeInKeychainToggleAction:(id)sender;

- (IBAction)jobFilterToggleAction:(id)sender;

@end
