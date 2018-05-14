//
//  Capture.m
//  JTCapture
//
//  Created by JT Ma on 30/11/2017.
//  Copyright © 2017 JT(ma.jiangtao.86@gmail.com). All rights reserved.
//

#import "Capture.h"

@interface Capture ()

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *deviceInput;

@end

@implementation Capture

// The method is deserted
- (instancetype)init {
     _sessionQueue = dispatch_queue_create("com.hiscene.sdk.captureSesstionQueue", DISPATCH_QUEUE_SERIAL);
    return [self initWithSessionPreset:AVCaptureSessionPresetHigh
                        devicePosition:AVCaptureDevicePositionBack
                          sessionQueue: _sessionQueue];
}

- (instancetype)initWithSessionPreset:(NSString *)sessionPreset
                       devicePosition:(AVCaptureDevicePosition)position
                         sessionQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        // Create the AVCaptureSession.
         _session = [[AVCaptureSession alloc] init];
        
        // Communicate with the session and other session objects on this queue.
         _sessionQueue = queue;
        
        _setupResult = AVCaptureSetupResultSuccess;
        
        _position = position; // AVCaptureDevicePositionBack
        _sessionPreset = sessionPreset; // AVCaptureSessionPresetHigh
        
        /*
         Check video authorization status. Video access is required and audio
         access is optional. If audio access is denied, audio is not recorded
         during movie recording.
         */
        switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] ) {
            case AVAuthorizationStatusAuthorized: {
                // The user has previously granted access to the camera.
                break;
            }
            case AVAuthorizationStatusNotDetermined: {
                /*
                 The user has not yet been presented with the option to grant
                 video access. We suspend the session queue to delay session
                 setup until the access request has completed.
                 
                 Note that audio access will be implicitly requested when we
                 create an AVCaptureDeviceInput for audio during session setup.
                 */
                dispatch_suspend(  _sessionQueue );
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                    if ( ! granted ) {
                        _setupResult = AVCaptureSetupResultCameraNotAuthorized;
                    }
                    dispatch_resume(  _sessionQueue );
                }];
                break;
            }
            default: {
                // The user has previously denied access.
                _setupResult = AVCaptureSetupResultCameraNotAuthorized;
                break;
            }
        }
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because -[AVCaptureSession startRunning] is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        dispatch_async(  _sessionQueue, ^{
            [self configureSession];
        } );
    }
    return self;
}

#pragma mark - Public

- (void)start {
    dispatch_async( _sessionQueue, ^{
        if (  _setupResult == AVCaptureSetupResultSuccess ) {
            [_session startRunning];
        }
    });
}

- (void)stop {
    dispatch_async( _sessionQueue, ^{
        if (_setupResult == AVCaptureSetupResultSuccess ) {
            [_session stopRunning];
        }
    });
}

- (void)setPosition:(AVCaptureDevicePosition)position {
    dispatch_async( _sessionQueue, ^{
        if (_position != position) {
            _position = position;
            if ( _setupResult != AVCaptureSetupResultSuccess) return;
            [self setPosition:position];
        }
    });
}

- (void)setFlashMode:(AVCaptureFlashMode)flashMode {
    dispatch_async( _sessionQueue, ^{
        if (_flashMode != flashMode) {
            _flashMode = flashMode;
            if ( _setupResult != AVCaptureSetupResultSuccess) return;
            [self setFlashMode:flashMode forDevice:_deviceInput.device];
        }
    });
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode {
    dispatch_async( _sessionQueue, ^{
        if (_torchMode != torchMode) {
            _torchMode = torchMode;
            if (_setupResult != AVCaptureSetupResultSuccess) return;
            [self setTorchMode:torchMode forDevice:_deviceInput.device];
        }
    });
}

- (void)setFocusMode:(AVCaptureFocusMode)focusMode {
    dispatch_async( _sessionQueue, ^{
        if (_focusMode != focusMode) {
            _focusMode = focusMode;
            if (_setupResult != AVCaptureSetupResultSuccess) return;
            [self setFocusMode:focusMode forDevice:_deviceInput.device];
        }
    });
}

- (void)setActiveVideoFrame:(NSInteger)activeVideoFrame {
    dispatch_async(_sessionQueue, ^{
        if (_activeVideoFrame != activeVideoFrame) {
            _activeVideoFrame = activeVideoFrame;
            if ( _setupResult != AVCaptureSetupResultSuccess) return;
            [self setActiveVideoFrame:_activeVideoFrame forDevice:_deviceInput.device];
        }
    });
}

#pragma mark - Private

- (void)configureSession {
    if ( _setupResult != AVCaptureSetupResultSuccess ) {
        return;
    }
    
    NSError *error = nil;
    
    /*
     We do not create an AVCaptureMovieFileOutput when setting up the session because the
     AVCaptureMovieFileOutput does not support movie recording with AVCaptureSessionPresetPhoto.
     */
    [ _session beginConfiguration];
     _session.sessionPreset =  _sessionPreset;
    [ _session commitConfiguration];
    
    // Add video input.
    AVCaptureDevice *device;
    // Choose the back dual camera if available, otherwise default to a wide angle camera.

    if (@available(iOS 10.0, *)) {
        device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDuoCamera mediaType:AVMediaTypeVideo position:_position];
        
        if ( ! device ) {
            // If the back dual camera is not available, default to the back wide angle camera.
            device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:_position];
        }
    } else {
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *d in devices) {
            if (d.position == _position) {
                device = d;
                break;
            }
        }
    }
    
    [self addDeviceInputWithDevice:device];
}

- (void)addDeviceInputWithDevice:(AVCaptureDevice *)device {
    [ _session beginConfiguration];
    
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if ( ! deviceInput ) {
#if DEBUG
        NSLog( @"Could not create video device input: %@", error );
#endif
        _setupResult = AVCaptureSetupResultSessionConfigurationFailed;
        [ _session commitConfiguration];
        return;
    }
    
    if ( [ _session canAddInput:deviceInput] ) {
        [ _session addInput:deviceInput];
        _deviceInput = deviceInput;
    } else {
#if DEBUG
        NSLog( @"Could not add video device input to the session" );
#endif
        _setupResult = AVCaptureSetupResultSessionConfigurationFailed;
        [ _session commitConfiguration];
        return;
    }
    
    [ _session commitConfiguration];
}

#pragma mark - Utils

- (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device {
    if ( device.hasFlash && [device isFlashModeSupported:flashMode] ) {
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        } else {
#if DEBUG
            NSLog( @"Could not lock device for configuration: %@", error );
#endif
        }
    }
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode forDevice:(AVCaptureDevice *)device {
    if ( device.hasTorch && [device isTorchModeSupported:torchMode] ) {
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            device.torchMode = torchMode;
            [device unlockForConfiguration];
        } else {
#if DEBUG
            NSLog( @"Could not lock device for configuration: %@", error );
#endif
        }
    }
}

- (void)setFocusMode:(AVCaptureFocusMode)focusMode forDevice:(AVCaptureDevice *)device {
    if ( [device isFocusModeSupported:focusMode] ) {
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            device.focusMode = focusMode;
            [device unlockForConfiguration];
        } else {
#if DEBUG
            NSLog( @"Could not lock device for configuration: %@", error );
#endif
        }
    }
}

- (void)setPosition:(AVCaptureDevicePosition)position {
    NSArray *availableCameraDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in availableCameraDevices) {
        if ( [device hasMediaType:AVMediaTypeVideo] ) {
            if (position == device.position) {
                [_session removeInput:_deviceInput];
                [self addDeviceInputWithDevice:device];
            }
        }
    }
}

- (void)setActiveVideoFrame:(NSInteger)activeVideoFrame forDevice:(AVCaptureDevice *)device {
    NSError *error;
    activeVideoFrame = MAX(0, MIN(60, activeVideoFrame));
    CMTime frameDuration = CMTimeMake(1, (int32_t)activeVideoFrame);
    NSArray *supportedFrameRateRanges = [device.activeFormat videoSupportedFrameRateRanges];
    BOOL frameRateSupported = NO;
    for (AVFrameRateRange *range in supportedFrameRateRanges) {
        if (CMTIME_COMPARE_INLINE(frameDuration, >=, range.minFrameDuration) &&
            CMTIME_COMPARE_INLINE(frameDuration, <=, range.maxFrameDuration)) {
            frameRateSupported = YES;
        }
    }
    
    if (frameRateSupported && [device lockForConfiguration:&error]) {
        [device setActiveVideoMaxFrameDuration:frameDuration];
        [device setActiveVideoMinFrameDuration:frameDuration];
        [device unlockForConfiguration];
    } else {
#if DEBUG
        NSLog( @"Could not lock device for configuration or not supported frame rate: %@", error );
#endif
    }
}

@end
