#import "ZebrautilityPlugin.h"
#import "TcpPrinterConnection.h"
#if __has_include(<zebrautil/zebrautil-Swift.h>)
#import <zebrautil/zebrautil-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "zebrautil-Swift.h"
#endif

@implementation ZebraUtilPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
//    TcpPrinterConnection *con =  [TcpPrinterConnection init];
  [SwiftZebraUtilPlugin registerWithRegistrar:registrar];
}
@end
