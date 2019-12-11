//
//  SentryPLCrashReporterIntegration.m
//  Sentry
//
//  Created by Klemens Mantzos on 11.12.19.
//  Copyright © 2019 Sentry. All rights reserved.
//

#if __has_include(<Sentry/Sentry.h>)

#import <Sentry/SentryPLCrashReporterIntegration.h>
#import <Sentry/SentryBreadcrumbTracker.h>
#import <Sentry/SentryOptions.h>
#import <Sentry/SentryLog.h>
#import <Sentry/SentryEvent.h>
//#import <PLCrashReporter/PLCrashReporter.h>
#else
#import "SentryPLCrashReporterIntegration.h"
#import "SentryBreadcrumbTracker.h"
#import "SentryOptions.h"
#import "SentryLog.h"
#import "SentryEvent.h"
#endif

#import <CrashReporter/CrashReporter.h>
#import <CrashReporter/PLCrashReporterConfig.h>

@interface SentryPLCrashReporterIntegration()

@property (nonatomic, strong) PLCrashReporter *crashReporter;

@end

@implementation SentryPLCrashReporterIntegration

- (nonnull NSString *)identifier {
    return NSStringFromClass([self class]);
}

- (BOOL)installWithOptions:(nonnull SentryOptions *)options {
    [self doInstall];
    return YES;
}

- (void)doInstall {
    //PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
    PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc] initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll shouldRegisterUncaughtExceptionHandler:YES];
    self.crashReporter = [[PLCrashReporter alloc] initWithConfiguration:config];

    NSError *error;

     // Check if we previously crashed
    if ([crashReporter hasPendingCrashReport]) {
         [self handleCrashReport];
    }

     // Enable the Crash Reporter
    if (![crashReporter enableCrashReporterAndReturnError: &error]) {
        NSLog(@"Warning: Could not enable crash reporter: %@", error);
    }
}

- (void) handleCrashReport {
    NSData *crashData;
    NSError *error;

    // Try loading the crash report
    crashData = [self.crashReporter loadPendingCrashReportDataAndReturnError: &error];
    if (crashData == nil) {
        NSLog(@"Could not load crash report: %@", error);
        [self.crashReporter purgePendingCrashReport];
        return;
    }

    // We could send the report from here, but we'll just print out
    // some debugging info instead
    PLCrashReport *report = [[PLCrashReport alloc] initWithData: crashData error: &error];
    if (report == nil) {
        NSLog(@"Could not parse crash report");
        [self.crashReporter purgePendingCrashReport];
        return;
    }

    NSLog(@"Crashed on %@", report.systemInfo.timestamp);
    NSLog(@"Crashed with signal %@ (code %@, address=0x%" PRIx64 ")", report.signalInfo.name,
          report.signalInfo.code, report.signalInfo.address);

    [self.crashReporter purgePendingCrashReport];
    return;
}

@end
