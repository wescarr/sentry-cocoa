//
//  SentryCrashMonitor_Tests.m
//
//  Created by Karl Stenerud on 2013-03-09.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <XCTest/XCTest.h>

#import "SentryCrashMonitor.h"
#import "SentryCrashMonitorContext.h"

@interface SentryCrashMonitor_Tests : XCTestCase
@end

@implementation SentryCrashMonitor_Tests

- (void)testInstallUninstall
{
    sentrycrashcm_setActiveMonitors(SentryCrashMonitorTypeAll);
    sentrycrashcm_setActiveMonitors(SentryCrashMonitorTypeNone);
}

- (void)testSuspendResumeThreads
{
    thread_act_array_t threads1 = NULL;
    mach_msg_type_number_t numThreads1 = 0;
    sentrycrashmc_suspendEnvironment(&threads1, &numThreads1);

    thread_act_array_t threads2 = NULL;
    mach_msg_type_number_t numThreads2 = 0;
    sentrycrashmc_suspendEnvironment(&threads2, &numThreads2);

    sentrycrashmc_resumeEnvironment(threads2, numThreads2);
    sentrycrashmc_resumeEnvironment(threads1, numThreads1);
}

@end
