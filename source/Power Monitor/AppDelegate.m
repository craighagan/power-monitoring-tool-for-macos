/*
     AppDelegate.m
     Copyright 2023-2025 SAP SE
     
     Licensed under the Apache License, Version 2.0 (the "License");
     you may not use this file except in compliance with the License.
     You may obtain a copy of the License at
     
     http://www.apache.org/licenses/LICENSE-2.0
     
     Unless required by applicable law or agreed to in writing, software
     distributed under the License is distributed on an "AS IS" BASIS,
     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
     See the License for the specific language governing permissions and
     limitations under the License.
*/

#import "AppDelegate.h"
#import "MTPowerMeasurement.h"
#import "MTPowerMeasurementReader.h"
#import "MTPowerMeasurementArray.h"
#import "Constants.h"
#import "MTCarbonFootprint.h"
#import "MTStatusItemMenu.h"
#import "MTPowerJournal.h"
#import "MTDaemonConnection.h"
#import "MTSystemInfo.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

@interface AppDelegate ()
@property (weak) IBOutlet MTStatusItemMenu *statusItemMenu;

@property (nonatomic, strong, readwrite) NSStatusItem *statusItem;
@property (nonatomic, strong, readwrite) NSUserDefaults *userDefaults;
@property (nonatomic, strong, readwrite) NSWindowController *mainWindowController;
@property (nonatomic, strong, readwrite) NSWindowController *settingsWindowController;
@property (nonatomic, strong, readwrite) MTCarbonFootprint *carbonFootprint;
@property (nonatomic, strong, readwrite) NSString *lastCurrentPowerValue;
@property (nonatomic, strong, readwrite) NSString *lastNegotiatedPowerValue;
@property (nonatomic, strong, readwrite) NSTimer *statusItemPowerTimer;
@property (assign) CFRunLoopSourceRef powerSourceRef __attribute__((NSObject));
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    _userDefaults = [NSUserDefaults standardUserDefaults];
    
    [_userDefaults registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorNamed:@"GraphFillColor"] requiringSecureCoding:YES error:nil], kMTDefaultsGraphFillColorKey,
                                     [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorNamed:@"GraphPowerNapFillColor"] requiringSecureCoding:YES error:nil], kMTDefaultsGraphPowerNapFillColorKey,
                                     [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorNamed:@"GraphAverageLineColor"] requiringSecureCoding:YES error:nil], kMTDefaultsGraphAverageColorKey,
                                     [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorNamed:@"GraphDayMarkerColor"] requiringSecureCoding:YES error:nil], kMTDefaultsGraphDayMarkerColorKey,
                                     [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorNamed:@"GraphPositionLineColor"] requiringSecureCoding:YES error:nil], kMTDefaultsGraphPositionLineColorKey,
                                     [NSNumber numberWithBool:YES], kMTDefaultsLogFollowCursorKey,
                                     [NSNumber numberWithDouble:0], kMTDefaultsElectricityPriceKey,
                                     [NSNumber numberWithDouble:0], kMTDefaultsAltElectricityPriceKey,
                                     nil]
    ];
    
    NSArray *appArguments = [[NSProcessInfo processInfo] arguments];
    
    if ([appArguments containsObject:@"--help"]) {
        
        [self printUsage];
        [NSApp terminate:self];
        
    } else if ([appArguments containsObject:@"--noGUI"]) {

        MTPowerMeasurementReader *pM = [[MTPowerMeasurementReader alloc] initWithContentsOfFile:kMTMeasurementFilePath];
        
        if (pM) {

            NSArray *allMeasurements = [pM allMeasurements];
            
            if ([appArguments containsObject:@"--journal"]) {
                
                MTPowerJournal *powerJournal = [[MTPowerJournal alloc] initWithFileAtPath:kMTJournalFilePath];
                
                if (powerJournal) {
                    
                    NSCalendarUnit summarize = 0;
                    NSArray *journalEntries = [powerJournal allEntries];
                    
                    NSInteger argumentIndex = [appArguments indexOfObject:@"--summarize"];
                    
                    if (argumentIndex != NSNotFound && [appArguments count] > argumentIndex + 1) {

                        NSString *summarizeString = [[appArguments objectAtIndex:argumentIndex + 1] lowercaseString];
                        
                        if ([summarizeString isEqualToString:@"w"]) {
                            
                            summarize = NSCalendarUnitWeekOfYear;
                            
                        } else if ([summarizeString isEqualToString:@"m"]) {
                            
                            summarize = NSCalendarUnitMonth;
                            
                        } else if ([summarizeString isEqualToString:@"y"]) {
                            
                            summarize = NSCalendarUnitYear;
                        }
                    }
                    
                    argumentIndex = [appArguments indexOfObject:@"--start"];
                    if (argumentIndex != NSNotFound && [appArguments count] > argumentIndex + 1) {
                        
                        NSString *dateString = [[appArguments objectAtIndex:argumentIndex + 1] lowercaseString];
                        
                        if (dateString) {
                            
                            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                            [dateFormatter setDateFormat:@"yyyy-MM-dd"];
                            NSDate *startDate = [dateFormatter dateFromString:dateString];
                            
                            if (startDate) {
                                
                                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"timeStamp >= %lf", [startDate timeIntervalSince1970]];
                                journalEntries = [journalEntries filteredArrayUsingPredicate:predicate];
                            }
                        }
                    }
                    
                    argumentIndex = [appArguments indexOfObject:@"--end"];
                    if (argumentIndex != NSNotFound && [appArguments count] > argumentIndex + 1) {
                        
                        NSString *dateString = [[appArguments objectAtIndex:argumentIndex + 1] lowercaseString];
                        
                        if (dateString) {
                            
                            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                            [dateFormatter setDateFormat:@"yyyy-MM-dd"];
                            NSDate *endDate = [dateFormatter dateFromString:dateString];
                            
                            if (endDate) {
                                
                                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"timeStamp <= %lf", [endDate timeIntervalSince1970]];
                                journalEntries = [journalEntries filteredArrayUsingPredicate:predicate];
                            }
                        }
                    }
                    
                    NSString *jsonString = [MTPowerJournal jsonStringWithEntries:journalEntries 
                                                                    summarizedBy:summarize
                                                                 includeDuration:YES
                    ];
                    printf("%s\n", [jsonString UTF8String]);
                }
                
                [NSApp terminate:self];
                
            } else {
                
                MTPowerMeasurement *averagePower = [allMeasurements averagePower];
                
                if ([averagePower doubleValue] > 0) {
                    
                    if ([appArguments containsObject:@"--averagePowerOnly"]) {
                        
                        printf("%.2f\n", [averagePower doubleValue]);
                        [NSApp terminate:self];
                        
                    } else {
                        
                        NSMutableDictionary *jsonDict = [[NSMutableDictionary alloc] init];
                        [jsonDict setObject:[NSNumber numberWithDouble:[[pM currentPower] doubleValue]] forKey:@"CurrentPower"];
                        [jsonDict setObject:[NSNumber numberWithDouble:[averagePower doubleValue]] forKey:@"AveragePower"];
                        [jsonDict setObject:[NSNumber numberWithInteger:[allMeasurements count]] forKey:@"MeasurementsCount"];
                        
                        _carbonFootprint = [[MTCarbonFootprint alloc] initWithAPIKey:nil];
                        [_carbonFootprint currentLocationWithCompletionHandler:^(CLLocation *location, BOOL preciseLocation) {
                            
                            [self->_carbonFootprint countryCodeWithLocation:location
                                                          completionHandler:^(NSString *countryCode) {
                                
                                [jsonDict setObject:(countryCode) ? countryCode : @"unknown" forKey:@"CountryCode"];
                                [jsonDict setObject:[NSNumber numberWithBool:preciseLocation] forKey:@"PreciseLocation"];
                                
                                // if we use a static list of carbon intensity values (either imported
                                // directly into the app or provided via configuration profile), we also
                                // print the carbon footprint value
                                NSDictionary *carbonRegions = [self->_userDefaults objectForKey:kMTDefaultsCarbonRegionsKey];
                                
                                if (countryCode && carbonRegions) {
                                    
                                    NSNumber *gramsCO2eqkWh = ([carbonRegions objectForKey:countryCode]) ? [carbonRegions valueForKey:countryCode] : [carbonRegions valueForKey:NSLocalizedStringFromTable(countryCode, @"Alpha-2toAlpha-3", nil)];
                                    
                                    if ([gramsCO2eqkWh floatValue] > 0) {
                                        
                                        NSMeasurement *measurementPowerKW = [averagePower measurementByConvertingToUnit:[NSUnitPower kilowatts]];
                                        NSMeasurement *measurementCarbon = [[NSMeasurement alloc] initWithDoubleValue:[measurementPowerKW doubleValue] * [gramsCO2eqkWh floatValue]
                                                                                                                 unit:[NSUnitMass grams]];
                                        [jsonDict setObject:[NSNumber numberWithDouble:[measurementCarbon doubleValue]] forKey:@"CarbonFootprint"];
                                        
                                    } else {
                                        
                                        [jsonDict setObject:[NSNumber numberWithInteger:-1] forKey:@"CarbonFootprint"];
                                    }
                                    
                                } else {
                                    
                                    [jsonDict setObject:[NSNumber numberWithInteger:-1] forKey:@"CarbonFootprint"];
                                }
                                
                                if ([appArguments containsObject:@"--JSON"]) {
                                    
                                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict
                                                                                       options:NSJSONWritingPrettyPrinted
                                                                                         error:nil
                                    ];

                                    if (jsonData) {
                                        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                        printf("%s\n", [jsonString UTF8String]);
                                    }
                                    
                                    
                                } else if ([appArguments containsObject:@"--footprintOnly"]) {
                                    
                                    double carbonValue = [[jsonDict valueForKey:@"CarbonFootprint"] doubleValue];
                                    
                                    if (carbonValue >= 0) {
                                        printf("%.2f\n", carbonValue);
                                    } else {
                                        printf("%.0f\n", carbonValue);
                                    }
                                    
                                } else {
                                    
                                    double carbonValue = [[jsonDict valueForKey:@"CarbonFootprint"] doubleValue];
                                    
                                    printf("Current system power (in W): %.2f\n", [[jsonDict valueForKey:@"CurrentPower"] doubleValue]);
                                    printf("Average system power (in W): %.2f\n", [[jsonDict valueForKey:@"AveragePower"] doubleValue]);
                                    printf("Number of measurements: %lu\n", [[jsonDict valueForKey:@"MeasurementsCount"] integerValue]);
                                    printf("Country code: %s\n", [[jsonDict valueForKey:@"CountryCode"] UTF8String]);
                                    printf("Precise location: %s\n", ([[jsonDict valueForKey:@"PreciseLocation"] boolValue]) ? "yes" : "no");
                                    
                                    if (carbonValue >= 0) {
                                        printf("Carbon footprint (in gCO2eq/h): %.2f\n", carbonValue);
                                    } else {
                                        printf("Carbon footprint (in gCO2eq/h): unavailable\n");
                                    }
                                }
                                
                                [NSApp terminate:self];
                            }];
                        }];
                    }
                    
                } else {
                    
                    printf("No measurements\n");
                    [NSApp terminate:self];
                }
            }
            
        } else {
            
            fprintf(stderr, "ERROR! Failed to access buffer file\n");
            [NSApp terminate:self];
        }
        
    } else {

        NSStoryboard *storyboard = [NSStoryboard storyboardWithName:@"Main" bundle:nil];
        _mainWindowController = [storyboard instantiateControllerWithIdentifier:@"corp.sap.PowerMonitor.MainController"];

        // run as status item or regular application
        [self runAsStatusItem:[_userDefaults boolForKey:kMTDefaultsRunInBackgroundKey]];

        // observe changes of the kMTDefaultsRunInBackgroundKey value
        [_userDefaults addObserver:self forKeyPath:kMTDefaultsRunInBackgroundKey options:NSKeyValueObservingOptionNew context:nil];

        // start polling for status item power display
        [self startStatusItemPowerUpdates];
    }
}

- (void)runAsStatusItem:(BOOL)status
{
    if (status) {

        if (!self->_statusItem) {

            self->_statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
            [[self->_statusItem button] setImage:[NSImage imageNamed:@"StatusItem"]];
            [self->_statusItem setMenu:self->_statusItemMenu];
        }
        
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (self->_mainWindowController) { [[self->_mainWindowController window] close]; }
        if (self->_settingsWindowController) { [[self->_settingsWindowController window] close]; }
        
    } else {
        
        if (_statusItem) {
            
            [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
            _statusItem = nil;
        }
            
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        
        if (_mainWindowController) {
            [_mainWindowController showWindow:nil];
            [[_mainWindowController window] makeKeyAndOrderFront:nil];
        }
        
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)printUsage
{
    fprintf(stderr, "\nUsage:\n\n");
    fprintf(stderr, "   Power Monitor --noGUI [--JSON]\n");
    fprintf(stderr, "   Power Monitor --noGUI [--averagePowerOnly | --footprintOnly]\n");
    fprintf(stderr, "   Power Monitor --noGUI --journal [--summarize <w|m|y>] [--start <date>] [--end <date>]\n\n");
    fprintf(stderr, "   --noGUI     If used without any additional arguments, it runs the application without gui and returns some basic information.\n\n");
    fprintf(stderr, "               --JSON              Returns the data in JSON format instead of plain text.\n\n");
    
    fprintf(stderr, "               --averagePowerOnly  Returns the average power value only.\n\n");
    
    fprintf(stderr, "               --footprintOnly     Returns the carbon footprint only.\n\n");
    
    fprintf(stderr, "               --journal           Returns the power journal in json format.\n\n");
    
    fprintf(stderr, "                                   --summarize <w|m|y>     Summarizes the journal by week, month or year.\n\n");
    
    fprintf(stderr, "                                   --start <date>          Returns the journal starting from the provided date. Date must be in format \"YYYY-MM-DD\".\n\n");
    
    fprintf(stderr, "                                   --end <date>            Returns the journal up to the provided date. Date must be in format \"YYYY-MM-DD\".\n\n");
    
    fprintf(stderr, "   --help      Shows this help.\n\n");
}

#pragma mark Dock Icon and Status Item Power Display

static void powerSourceDidChange(void *context)
{
    AppDelegate *self = (__bridge AppDelegate *)context;
    [self updatePowerDisplay];
}

- (void)startStatusItemPowerUpdates
{
    // update immediately
    [self updatePowerDisplay];

    // register for power source change events (adapter plug/unplug)
    self.powerSourceRef = IOPSNotificationCreateRunLoopSource(powerSourceDidChange, (__bridge void *)self);
    CFRunLoopAddSource(CFRunLoopGetMain(), self.powerSourceRef, kCFRunLoopDefaultMode);

    // poll every 10 seconds for current system power (which fluctuates)
    _statusItemPowerTimer = [NSTimer scheduledTimerWithTimeInterval:kMTCurrentPowerUpdateInterval
                                                            repeats:YES
                                                              block:^(NSTimer *timer) {
        [self updatePowerDisplay];
    }];
    [[NSRunLoop currentRunLoop] addTimer:_statusItemPowerTimer forMode:NSEventTrackingRunLoopMode];
}

- (void)updatePowerDisplay
{
    float currentWatts = [MTSystemInfo rawSystemPower];
    NSInteger negotiatedWatts = [MTSystemInfo negotiatedPowerAdapterWatts];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateDockIconWithCurrentPower:currentWatts negotiatedPower:negotiatedWatts];
        [self updateStatusItemWithCurrentPower:currentWatts negotiatedPower:negotiatedWatts];
    });
}

- (void)updateDockIconWithCurrentPower:(float)currentWatts negotiatedPower:(NSInteger)negotiatedWatts
{
    // always show current draw (0W on battery is valid)
    NSString *line1 = [NSString stringWithFormat:@"%ldW", (long)lroundf(currentWatts)];
    NSString *line2 = (negotiatedWatts > 0) ? [NSString stringWithFormat:@"%ldW", (long)negotiatedWatts] : nil;

    NSSize size = NSMakeSize(128, 128);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];

    // draw green rounded rect background
    NSColor *greenBg = [NSColor colorWithCalibratedHue:0.38 saturation:0.75 brightness:0.72 alpha:1.0];
    [greenBg setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size.width, size.height) xRadius:24 yRadius:24] fill];

    if (line2) {
        // two lines: current on top, negotiated on bottom
        NSDictionary *textAttrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:36],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        };

        NSAttributedString *attrLine1 = [[NSAttributedString alloc] initWithString:line1 attributes:textAttrs];
        NSAttributedString *attrLine2 = [[NSAttributedString alloc] initWithString:line2 attributes:textAttrs];

        NSSize size1 = [attrLine1 size];
        NSSize size2 = [attrLine2 size];

        CGFloat totalHeight = size1.height + size2.height + 2;
        CGFloat startY = (size.height - totalHeight) / 2;

        [attrLine2 drawAtPoint:NSMakePoint((size.width - size2.width) / 2, startY)];
        [attrLine1 drawAtPoint:NSMakePoint((size.width - size1.width) / 2, startY + size2.height + 2)];

    } else {
        // single line centered (battery / no adapter)
        NSDictionary *largeAttrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:46],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        };
        NSAttributedString *attrLine = [[NSAttributedString alloc] initWithString:line1 attributes:largeAttrs];
        NSSize textSize = [attrLine size];
        [attrLine drawAtPoint:NSMakePoint((size.width - textSize.width) / 2, (size.height - textSize.height) / 2)];
    }

    [image unlockFocus];
    [NSApp setApplicationIconImage:image];
}

- (void)updateStatusItemWithCurrentPower:(float)currentWatts negotiatedPower:(NSInteger)negotiatedWatts
{
    if (!_statusItem) { return; }

    NSMutableString *title = [[NSMutableString alloc] init];

    if (currentWatts > 0) {
        [title appendFormat:@"%ldW", (long)lroundf(currentWatts)];
    }

    if (negotiatedWatts > 0) {
        if ([title length] > 0) { [title appendString:@"/"]; }
        [title appendFormat:@"%ldW", (long)negotiatedWatts];
    }

    if ([title length] > 0) {
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightRegular]
        };
        NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:title attributes:attributes];
        [[_statusItem button] setAttributedTitle:attrTitle];
        [[_statusItem button] setImage:nil];
    } else {
        [[_statusItem button] setTitle:@""];
        [[_statusItem button] setImage:[NSImage imageNamed:@"StatusItem"]];
    }
}

#pragma mark IBActions

- (IBAction)showSettingsWindow:(id)sender
{
    if (!_settingsWindowController) {
        
        NSStoryboard *storyboard = [NSStoryboard storyboardWithName:@"Main" bundle:nil];
        _settingsWindowController = [storyboard instantiateControllerWithIdentifier:@"corp.sap.PowerMonitor.SettingsController"];
    }
    
    [_settingsWindowController showWindow:nil];
    [[_settingsWindowController window] makeKeyAndOrderFront:nil];
    
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)showMainWindow:(id)sender
{
    if (_mainWindowController) {
        [_mainWindowController showWindow:nil];
        [[_mainWindowController window] makeKeyAndOrderFront:nil];        
    }
}

- (IBAction)showConsoleWindow:(id)sender
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationNameShowConsole
                                                        object:nil
                                                      userInfo:nil
    ];
}

- (IBAction)showGraphWindow:(id)sender
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationNameShowGraphWindow
                                                        object:nil
                                                      userInfo:nil
    ];
}

- (IBAction)openGitHub:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kMTGitHubURL]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:kMTDefaultsRunInBackgroundKey]) {
        
        [self runAsStatusItem:[_userDefaults boolForKey:kMTDefaultsRunInBackgroundKey]];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if (!flag) {
        if (_mainWindowController) {
            [_mainWindowController showWindow:nil];
            [[_mainWindowController window] makeKeyAndOrderFront:nil];
        }
    }
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{

}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
    return YES;
}

@end
