// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//
//  J2ObjCMain.m
//  JreEmulation
//
//  Main function that provides JVM-like start-up for OS X.
//  Usage: <executable> <class-with-Java-main-method> [args]
//

#import "JreEmulation.h"
#import "IOSClass.h"
#include "IOSObjectArray.h"
#include "NSException+JavaThrowable.h"
#include "java/io/PrintStream.h"
#include "java/lang/ClassNotFoundException.h"
#include "java/lang/IllegalAccessException.h"
#include "java/lang/NoSuchMethodException.h"
#include "java/lang/System.h"
#include "java/lang/Thread.h"
#include "java/lang/reflect/InvocationTargetException.h"
#include "java/lang/reflect/Method.h"

#include <execinfo.h>

static void signalHandler(int sig) {
  // Get void*'s for all entries on the stack.
  void *array[64];
  int frame_count = (int) backtrace(array, 64);

  // Print all the frames to stderr.
  fprintf(stderr, "Error: signal %d:\n", sig);
  backtrace_symbols_fd(array, frame_count, 2);
  exit(1);
}

void installSignalHandler() {
  signal(SIGABRT, signalHandler);
  signal(SIGILL, signalHandler);
  signal(SIGSEGV, signalHandler);
  signal(SIGFPE, signalHandler);
  signal(SIGBUS, signalHandler);
  signal(SIGPIPE, signalHandler);
}

void handleUncaughtException(NSException *e) {
  JavaLangThread *currentThread = JavaLangThread_currentThread();
  id uncaughtHandler = [currentThread getUncaughtExceptionHandler];
  [uncaughtHandler uncaughtExceptionWithJavaLangThread:currentThread withNSException:e];
}

// Converts main() arguments into an IOSObjectArray of NSStrings.  The first
// argument, the program name, is skipped so the returned array matches what
// is passed to a Java main method.
IOSObjectArray *JreEmulationMainArguments(int argc, const char *argv[]) {
  IOSClass *stringType = NSString_class_();
  if (argc <= 1) {
    return [IOSObjectArray arrayWithLength:0 type:stringType];
  }
  IOSObjectArray *args = [IOSObjectArray arrayWithLength:argc - 1 type:stringType];
  for (int i = 1; i < argc; i++) {
    NSString *arg =
    [NSString stringWithCString:argv[i]
                       encoding:[NSString defaultCStringEncoding]];
    IOSObjectArray_Set(args, i - 1, arg);
  }
  return args;
}

int main( int argc, const char *argv[] ) {
  if (argc < 2) {
    printf("Usage: %s class [args...]\n", *argv);
    return 1;
  }
  JrePrintNilChkCountAtExit();
  installSignalHandler();
  @autoreleasepool {
    const char *className = argv[1];
    IOSClass *clazz = nil;
    JavaLangReflectMethod *mainMethod = nil;

    // Find the main class.
    @try {
      clazz = [IOSClass forName:[NSString stringWithUTF8String:className]];
    }
    @catch (JavaLangClassNotFoundException *e) {
      fprintf(stderr, "Error: could not find or load main class %s\n",
              className);
      return 1;
    }

    // Find the main method.
    @try {
      IOSClass *stringArrayClass = IOSClass_arrayOf(NSString_class_());
      IOSObjectArray *paramTypes =
          [IOSObjectArray arrayWithObjects:(id[]) { stringArrayClass }
                                     count:1
                                      type:IOSClass_class_()];
      mainMethod = [clazz getDeclaredMethod:@"main" parameterTypes:paramTypes];
    }
    @catch (JavaLangNoSuchMethodException *e) {
      fprintf(stderr, "Error: main method not found in class %s\n", className);
      return 1;
    }

    // Execute the main method.
    @try {
      IOSObjectArray *mainArgs = JreEmulationMainArguments(argc - 1, &argv[1]);
      IOSObjectArray *params =
          [IOSObjectArray arrayWithObjects:(id[]) { mainArgs }
                                     count:1
                                      type:NSObject_class_()];
      (void) [mainMethod invokeWithId:nil withNSObjectArray:params];
    }
    @catch (JavaLangReflectInvocationTargetException *e) {
      handleUncaughtException([e getCause]);
      return 1;
    }
    @catch (JavaLangIllegalAccessException *e) {
      handleUncaughtException(e);
      return 1;
    }
    @catch (NSException *e) {
      handleUncaughtException(e);
    }
  }
  return 0;
}
