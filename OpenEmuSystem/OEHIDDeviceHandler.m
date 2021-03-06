/*
 Copyright (c) 2012, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "OEHIDDeviceHandler.h"
#import "OEControllerDescription.h"
#import "OEDeviceDescription.h"
#import "OEControlDescription.h"
#import "OEHIDEvent.h"
#import "OEDeviceManager.h"
#import "OEHIDDeviceParser.h"

NS_ASSUME_NONNULL_BEGIN

@interface OEHIDEvent ()
+ (instancetype)OE_eventWithElement:(IOHIDElementRef)element value:(NSInteger)value;
+ (instancetype)OE_initWithArgs:(OEDeviceHandler *)aDeviceHandler timestamp:(NSTimeInterval)timestamp cookie:(NSUInteger)cookie eventType:(OEHIDEventType)eventType axis:(OEHIDEventAxis)axis axisDirection:(OEHIDEventAxisDirection)axisDirection axisValue:(CGFloat)axisValue buttonNumber:(NSUInteger)buttonNumber buttonState:(OEHIDEventState)buttonState hatSwitchType:(OEHIDEventHatSwitchType)hatSwitchType hatDirection:(OEHIDEventHatDirection)hatDirection keyCode:(NSUInteger)keyCode keyState:(OEHIDEventState)keyState;

/* mods below */
- (NSString *)getType;
- (NSString *)getAxis;
- (NSString *)getAxisDirection;
- (NSString *)getAxisValue;
- (NSString *)getButtonNumber;
- (NSString *)getButtonState;
- (NSString *)getHatSwitchType;
- (NSString *)getHatDirection;
- (NSString *)getKeyState;
- (NSString *)getKeyCode;
/* mods above */
@end

@interface OEDeviceManager ()
- (void)OE_removeDeviceHandler:(OEDeviceHandler *)handler;
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

@implementation OEHIDDeviceHandler {
    NSMutableDictionary<NSNumber *, OEHIDEvent *> *_latestEvents;

    //force feedback support
    FFDeviceObjectReference _ffDevice;
    FFEFFECT *_effect;
    FFCUSTOMFORCE *_customforce;
    FFEffectObjectReference _effectRef;
    NSString *_desktopPath;
    NSString *_OpenEmuControllerLogFile;
    NSString *_outPutData;
    NSFileHandle *_fileHandle;
    int _lines;
}

+ (id<OEHIDDeviceParser>)deviceParser;
{
    static OEHIDDeviceParser *parser = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        parser = [[OEHIDDeviceParser alloc] init];
    });

    return parser;
}

- (instancetype)initWithDeviceDescription:(nullable OEDeviceDescription *)deviceDescription
{
    return nil;
}

- (instancetype)initWithIOHIDDevice:(IOHIDDeviceRef)aDevice deviceDescription:(nullable OEDeviceDescription *)deviceDescription;
{
    if(aDevice == NULL)
        return nil;

    if((self = [super initWithDeviceDescription:deviceDescription])) {
        _device = (void *)CFRetain(aDevice);
        NSAssert(deviceDescription != nil || [self isKeyboardDevice], @"Non-keyboard devices must have device descriptions.");
        if(deviceDescription != nil) {
            _latestEvents = [[NSMutableDictionary alloc] initWithCapacity:[[self controllerDescription] numberOfControls]];
            [self OE_setUpInitialEvents];
        }

        [self OE_setUpCallbacks];
    }

    _desktopPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
    _OpenEmuControllerLogFile = [_desktopPath stringByAppendingPathComponent:@"OpenEmuControllerLog.txt"];
    _lines = 0;
    return self;
}

- (void)dealloc
{
    if (_device == NULL)
        return;

    CFRelease(_device);

    if(_ffDevice != NULL)
        FFReleaseDevice(_ffDevice);
}

- (NSString *)uniqueIdentifier
{
    return [[self locationID] stringValue];
}

- (NSString *)serialNumber
{
    return (__bridge NSString *)IOHIDDeviceGetProperty(_device, CFSTR(kIOHIDSerialNumberKey));
}

- (NSString *)manufacturer
{
    return (__bridge NSString *)IOHIDDeviceGetProperty(_device, CFSTR(kIOHIDManufacturerKey));
}

- (NSString *)product
{
    return (__bridge NSString *)IOHIDDeviceGetProperty(_device, CFSTR(kIOHIDProductKey));
}

- (NSUInteger)vendorID
{
    return [(__bridge NSNumber *)IOHIDDeviceGetProperty(_device, CFSTR(kIOHIDVendorIDKey)) integerValue];
}

- (NSUInteger)productID
{
    return [(__bridge NSNumber *)IOHIDDeviceGetProperty(_device, CFSTR(kIOHIDProductIDKey)) integerValue];
}

- (NSNumber *)locationID
{
    return (__bridge NSNumber *)IOHIDDeviceGetProperty(_device, CFSTR(kIOHIDLocationIDKey));
}

- (BOOL)isKeyboardDevice;
{
    return IOHIDDeviceConformsTo(_device, kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard);
}

- (void)dispatchEvent:(OEHIDEvent *)event
{
    if(event == nil){
        return;
    }

    NSNumber *cookieKey = @([event cookie]);
    OEHIDEvent *existingEvent = _latestEvents[cookieKey];

    if([event isEqualToEvent:existingEvent])
        return;

    NSTimeInterval seconds = [NSDate timeIntervalSinceReferenceDate];
    double timenumber = seconds*1000;
    NSNumber *myDoubleNumber = [NSNumber numberWithDouble:timenumber];
    NSString *timestring = [myDoubleNumber stringValue];

    //NSString *description = [event displayDescription];

    NSString *eventType = [event getType];
    
    NSString *axis = [event getAxis];
    NSString *axisDirection = [event getAxisDirection];
    NSString *axisValue = [event getAxisValue];


    NSString *buttonNumber = [event getButtonNumber];
    NSString *buttonState = [event getButtonState];

    NSString *hatSwitchType = [event getHatSwitchType];
    NSString *hatDirection = [event getHatDirection];
    
    NSString *keyState = [event getKeyState];
    NSString *keyCode = [event getKeyCode];


    NSString *outputString;
    outputString = [NSString stringWithFormat:@"timestring (in ms): %1$@, eventType: %2$@, cookieKey:%3$@, axis:%4$@, axisDirection:%5$@, axisValue:%6$@, buttonNumber:%7$@, buttonState:%8$@, hatSwitchType:%9$@, hatDirection:%10$@, keyState:%11$@, keyCode:%12$@\n", 
        timestring, 
        eventType, cookieKey,
        axis, axisDirection, axisValue,
        buttonNumber, buttonState,
        hatSwitchType, hatDirection,
        keyState, keyCode
    ];
    //NSLog(@"%@", outputString);

    _outPutData = [NSString stringWithFormat:@"%1$@%2$@", _outPutData, outputString];
    _lines++;
    if (_lines > 64) {
        NSError *error;
        _fileHandle = [NSFileHandle fileHandleForWritingAtPath:_OpenEmuControllerLogFile];
        if (_fileHandle){
            [_fileHandle seekToEndOfFile];
            [_fileHandle writeData:[_outPutData dataUsingEncoding:NSUTF8StringEncoding]];
            [_fileHandle closeFile];
        }
        else{
            [_outPutData writeToFile:_OpenEmuControllerLogFile
                      atomically:NO
                        encoding:NSStringEncodingConversionAllowLossy
                           error:&error];
        }
        NSLog(@"data written to file");
        _outPutData = @"";
        _lines = 0;
    }    

    if([event isAxisDirectionOppositeToEvent:existingEvent])
        [[OEDeviceManager sharedDeviceManager] deviceHandler:self didReceiveEvent:[event axisEventWithDirection:OEHIDEventAxisDirectionNull]];

    _latestEvents[cookieKey] = event;
    [[OEDeviceManager sharedDeviceManager] deviceHandler:self didReceiveEvent:event];
}

- (OEHIDEvent *)eventWithHIDValue:(IOHIDValueRef)aValue
{
    return [OEHIDEvent eventWithDeviceHandler:self value:aValue];
}

- (void)dispatchEventWithHIDValue:(IOHIDValueRef)aValue
{
    [self dispatchEvent:[self eventWithHIDValue:aValue]];
}

- (io_service_t)serviceRef
{
	return IOHIDDeviceGetService(_device);
}

//- (BOOL)connect
//{
// Example code to test the vibration.
//    [self enableForceFeedback];
//    dispatch_queue_t rumbleTest = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
//    dispatch_async(rumbleTest, ^{
//        while(true) {
//            [self rumbleWithStrongIntensity:0xFF weakIntensity:0xFF];
//            usleep(100);
//        }
//    });
//    return YES;
//}

- (void)forceFeedbackWithStrongIntensity:(CGFloat)strongIntensity weakIntensity:(CGFloat)weakIntensity
{
    if(_ffDevice == NULL)
        [self enableForceFeedback];

    if(_ffDevice  == NULL)
        return;

    if(_effectRef == NULL)
        return;

    _customforce->rglForceData[0] = strongIntensity * 10000;
    _customforce->rglForceData[1] = weakIntensity * 10000;
    FFEffectSetParameters(_effectRef, _effect, FFEP_TYPESPECIFICPARAMS);
    FFEffectStart(_effectRef, 1, 0);
}

- (BOOL)supportsForceFeedback
{
	io_service_t service = [self serviceRef];
	if(service == MACH_PORT_NULL)
        return NO;

    return FFIsForceFeedback(service) == FF_OK;
}

- (void)enableForceFeedback
{
	if(![self supportsForceFeedback])
        return;

    io_service_t service = [self serviceRef];
    if(service == MACH_PORT_NULL)
        return;

    FFCreateDevice(service, &_ffDevice);
    FFCAPABILITIES capabs;
    FFDeviceGetForceFeedbackCapabilities(_ffDevice, &capabs);

    // TODO: adjust for less than one axis of feedback
    if(capabs.numFfAxes != 2)
        return;

    _effect      = calloc(1, sizeof(FFEFFECT));
    _customforce = calloc(1, sizeof(FFCUSTOMFORCE));
    LONG  *c = calloc(2, sizeof(LONG));
    DWORD *a = calloc(2, sizeof(DWORD));
    LONG  *d = calloc(2, sizeof(LONG));

    c[0] = 0;
    c[1] = 0;
    a[0] = capabs.ffAxes[0];
    a[1] = capabs.ffAxes[1];
    d[0] = 0;
    d[1] = 0;

    _customforce->cChannels      = 2;
    _customforce->cSamples       = 2;
    _customforce->rglForceData   = c;
    _customforce->dwSamplePeriod = 100*1000;

    _effect->cAxes                 = capabs.numFfAxes;
    _effect->rglDirection          = d;
    _effect->rgdwAxes              = a;
    _effect->dwSamplePeriod        = 0;
    _effect->dwGain                = 10000;
    _effect->dwFlags               = FFEFF_OBJECTOFFSETS | FFEFF_SPHERICAL;
    _effect->dwSize                = sizeof(FFEFFECT);
    _effect->dwDuration            = FF_INFINITE;
    _effect->dwSamplePeriod        = 100 * 1000;
    _effect->cbTypeSpecificParams  = sizeof(FFCUSTOMFORCE);
    _effect->lpvTypeSpecificParams = _customforce;
    _effect->lpEnvelope            = NULL;
    FFDeviceCreateEffect(_ffDevice, kFFEffectType_CustomForce_ID, _effect, &_effectRef);
}

- (void)disableForceFeedback
{
	if(_ffDevice == NULL)
        return;

    FFDeviceReleaseEffect(_ffDevice, _effectRef);
    FFReleaseDevice(_ffDevice);
    _ffDevice = NULL;
}

- (void)OE_setUpInitialEvents;
{
    for(OEControlDescription *control in [[self controllerDescription] controls]) {
        OEHIDEvent *event = [control genericEvent];
        _latestEvents[@([event cookie])] = [[event nullEvent] eventWithDeviceHandler:self];
    }
}

- (void)OE_setUpCallbacks;
{
    // Register for removal
    IOHIDDeviceRegisterRemovalCallback(_device, OEHandle_DeviceRemovalCallback, (__bridge void *)self);

    // Register for input
    IOHIDDeviceRegisterInputValueCallback(_device, OEHandle_InputValueCallback, (__bridge void *)self);

    // Attach to the runloop
    IOHIDDeviceScheduleWithRunLoop(_device, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
}

- (void)OE_removeDeviceHandlerForDevice:(IOHIDDeviceRef)aDevice
{
    NSAssert(aDevice == _device, @"Device remove callback called on the wrong object.");

	IOHIDDeviceUnscheduleFromRunLoop(_device, CFRunLoopGetMain(), kCFRunLoopDefaultMode);

    if (_lines > 0)  {
        NSError *error;
        _fileHandle = [NSFileHandle fileHandleForWritingAtPath:_OpenEmuControllerLogFile];
        if (_fileHandle){
            [_fileHandle seekToEndOfFile];
            [_fileHandle writeData:[_outPutData dataUsingEncoding:NSUTF8StringEncoding]];
            [_fileHandle closeFile];
        }
        else{
            [_outPutData writeToFile:_OpenEmuControllerLogFile
                      atomically:NO
                        encoding:NSStringEncodingConversionAllowLossy
                           error:&error];
        }
        NSLog(@"data written to file");
        _lines = 0;
        _outPutData = @"";
    }

    [[OEDeviceManager sharedDeviceManager] OE_removeDeviceHandler:self];
}

static void OEHandle_InputValueCallback(void *inContext, IOReturn inResult, void *inSender, IOHIDValueRef inIOHIDValueRef)
{
    [(__bridge OEHIDDeviceHandler *)inContext dispatchEventWithHIDValue:inIOHIDValueRef];
}

static void OEHandle_DeviceRemovalCallback(void *inContext, IOReturn inResult, void *inSender)
{
	IOHIDDeviceRef hidDevice = (IOHIDDeviceRef)inSender;

	[(__bridge OEHIDDeviceHandler *)inContext OE_removeDeviceHandlerForDevice:hidDevice];
}

@end

#pragma clang diagnostic pop

NS_ASSUME_NONNULL_END
