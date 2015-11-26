#import "RedXcode.h"
#import "ORRedXcodePatternBackgroundView.h"

@import QuartzCore;

static RedXcode *sharedPlugin;

static CGFloat ORHueShiftAmount = 27.31;
static NSString *ORHueShiftKey = @"ORHueShiftKey";

@interface NSObject (IDEKit)
+ (id) workspaceWindowControllers;
@end

// https://bugs.webkit.org/attachment.cgi?id=234725&action=prettypatch
@interface NSView (AppKitDetails)
- (void)_addKnownSubview:(NSView *)subview;
@end

@interface RedXcode()

@property (nonatomic, copy) NSImage *appIcon;

@end

@implementation RedXcode

+ (void)pluginDidLoad:(NSBundle *)plugin
{
    static id sharedPlugin = nil;
    static dispatch_once_t onceToken;
    NSString *currentApplicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    if ([currentApplicationName isEqual:@"Xcode"]) {
        dispatch_once(&onceToken, ^{
            sharedPlugin = [[self alloc] initWithBundle:plugin];
        });
    }
}

- (id)initWithBundle:(NSBundle *)plugin
{
    self = [super init];
    if (!self) return nil;

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
          ORHueShiftKey: @(ORHueShiftAmount)
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidFinishLaunching:)
                                                 name:NSApplicationDidFinishLaunchingNotification
                                               object:nil];
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSApplicationDidFinishLaunchingNotification
                                                  object:nil];
    self.appIcon = [NSApplication sharedApplication].applicationIconImage;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willBuild:)
                                                 name:@"IDEBuildOperationWillStartNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBuild:)
                                                 name:@"IDEBuildOperationDidStopNotification"
                                               object:nil];
}

- (void)willBuild:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self changeWindows];
        [NSApplication sharedApplication].applicationIconImage = [self coloredImage:self.appIcon];
    });
}

- (void)didBuild:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self restoreWindows];
        [NSApplication sharedApplication].applicationIconImage = self.appIcon;
    });
}

- (void)changeWindows
{
    @try {
        NSArray *workspaceWindowControllers = [NSClassFromString(@"IDEWorkspaceWindowController") workspaceWindowControllers];
        for (NSWindow *window in [workspaceWindowControllers valueForKey:@"window"]) {
            [self setupStripeViewForWindow:window];
        }
    }
    @catch (NSException *exception) { }
}

- (void)restoreWindows
{
    @try {
        NSArray *workspaceWindowControllers = [NSClassFromString(@"IDEWorkspaceWindowController") workspaceWindowControllers];
        for (NSWindow *window in [workspaceWindowControllers valueForKey:@"window"]) {
            [self restoreStripeViewForWindow:window];
        }
    }
    @catch (NSException *exception) { }
}

static CGFloat ORRedXcodeStripeTag = 2324;

- (void)setupStripeViewForWindow:(NSWindow *)window
{
    if ([window isKindOfClass:NSClassFromString(@"IDEWorkspaceWindow")]) {
        NSView *windowFrameView = [[window contentView] superview];

        // Idea politely stolen from @zats: https://github.com/zats/BetaWarpaint
        
        NSImageView *stripeView = [windowFrameView viewWithTag:ORRedXcodeStripeTag];

        if (!stripeView) {
            CGFloat h = CGRectGetHeight(windowFrameView.bounds);
            CGFloat w = CGRectGetWidth(windowFrameView.bounds);

//            This lies on Yosemite
//            CGRect windowFrame = [NSWindow contentRectForFrameRect:window.frame styleMask: window.styleMask];
//            CGFloat toolbarHeight = NSHeight(windowFrame) - NSHeight([window.contentView frame]);

            CGFloat toolbarHeight = 38;

            stripeView = (id)[[ORRedXcodePatternBackgroundView alloc] initWithFrame:CGRectMake(0, h - toolbarHeight, w, toolbarHeight)];
            stripeView.tag = ORRedXcodeStripeTag;
            stripeView.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin | NSViewWidthSizable;
            [stripeView setWantsLayer:YES];
            [stripeView unregisterDraggedTypes];

            if ([windowFrameView respondsToSelector:@selector(_addKnownSubview:)]) {
                [(id)windowFrameView _addKnownSubview:stripeView];
            } else {
                [windowFrameView addSubview:stripeView];
            }
        }

    }
}

- (void)restoreStripeViewForWindow:(NSWindow *)window {
    if ([window isKindOfClass:NSClassFromString(@"IDEWorkspaceWindow")]) {
        NSView *windowFrameView = [[window contentView] superview];
        NSImageView *stripeView = [windowFrameView viewWithTag:ORRedXcodeStripeTag];
        if (stripeView) {
            [stripeView removeFromSuperview];
        }
    }
}

- (NSImage *)coloredImage:(NSImage *)image
{
    CIImage *inputImage = [[CIImage alloc] initWithData:[image TIFFRepresentation]];

    CIFilter *hueAdjust = [CIFilter filterWithName:@"CIHueAdjust"];
    [hueAdjust setValue: inputImage forKey: @"inputImage"];

    NSNumber *colorValue = [[NSUserDefaults standardUserDefaults] objectForKey:ORHueShiftKey];
    [hueAdjust setValue:colorValue forKey: @"inputAngle"];

    CIImage *outputImage = [hueAdjust valueForKey: @"outputImage"];
    NSImage *resultImage = [[NSImage alloc] initWithSize:[outputImage extent].size];
    NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage:outputImage];
    [resultImage addRepresentation:rep];

    return resultImage;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
