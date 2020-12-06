//
//  GJJanusVideoRoom.m
//  GJJanusDemo
//
//  Created by melot on 2018/3/14.
//

#import "GJJanusVideoRoom.h"
#import "Tools.h"
#import "GJJanusSubscriberRole.h"
#import "GJJanusPublishRole.h"
#import <WebRTC/RTCSessionDescription.h>
#import <WebRTC/WebRTC.h>
#import <WebRTC/RTCCameraVideoCapturer.h>
#import <WebRTC/RTCCameraPreviewView.h>
#import <WebRTC/RTCLogging.h>
#import <UIKit/UIView.h>
#import "KKRTCDefine+private.h"
#import "KKRTCVideoCapturer.h"
//#import "GJLog.h"
typedef enum VideoRoomMessageId{
    kVideoRoomJoin = 10 ,
}VideoRoomMessageId;

//#define GOOGLE_ICE @"stun:stun.l.google.com:19302"



static NSString* vidoeRoomMessage[] = {
    @"join",
};


@implementation GJJanusView
+(Class)layerClass{
    return [RTCCameraPreviewView class];
}
@end



@interface GJJanusVideoRoom()<GJJanusDelegate,GJJanusRoleDelegate,GJJanusSubscriberRoleDelegate>
{
    NSString* _userID;
    NSString* _display;
    NSString* _appId;
    NSString* _token;

    NSString* _myID;
    NSString* _myPvtId;
    
    
//    KKRTCVideoCapturer* _hideCamera;
    NSRecursiveLock*    _lock;//
    
}
@property(nonatomic,strong)NSMutableDictionary<NSString *,GJJanusSubscriberRole*>* remotes;
@property(nonatomic,strong,readonly)GJJanus* janus;
@property(nonatomic,assign)NSString* roomID;
@property(nonatomic,retain)GJJanusPublishRole* publlisher;
@property(nonatomic,retain)NSMutableDictionary<NSString *, KKRTCCanvas*>* canvas;

@end

static GJJanusVideoRoom* _shareJanusInstance;
@implementation GJJanusVideoRoom

+(instancetype)allocWithZone:(struct _NSZone *)zone{
    if (_shareJanusInstance == nil) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            _shareJanusInstance = [super allocWithZone:zone];
        });
    }
    return _shareJanusInstance;
}
+(instancetype)shareInstanceWithServer:(NSURL*)server delegate:(id<GJJanusVideoRoomDelegate>)delegate{
    if (_shareJanusInstance == nil) {
        _shareJanusInstance = [[GJJanusVideoRoom alloc]initWithServer:server delegate:delegate];
    }else{
        if (_shareJanusInstance.delegate != delegate){
        _shareJanusInstance.delegate = delegate;
        }
        if (![_shareJanusInstance.janus.server.absoluteString isEqualToString:server.absoluteString]) {
            [_shareJanusInstance updateJanusWithServer:server];
        }
    }
    return _shareJanusInstance;
}

-(instancetype)initWithServer:(NSURL *)server delegate:(id<GJJanusVideoRoomDelegate>)delegate{
    if (self = [super init]) {
        _delegate = delegate;
        _janus = [[GJJanus alloc]initWithServer:server delegate:self];
        _remotes = [NSMutableDictionary dictionaryWithCapacity:1];
        _canvas = [NSMutableDictionary dictionaryWithCapacity:2];
        _publlisher = [[GJJanusPublishRole alloc]initWithJanus:_janus delegate:self];
        _cameraPosition = AVCaptureDevicePositionFront;
        _lock = [[NSRecursiveLock alloc]init];
        RTCSetMinDebugLogLevel(RTCLoggingSeverityInfo);
    }
    return self;
}

-(void)setPreviewMirror:(BOOL)previewMirror{
    _previewMirror = previewMirror;
    [_publlisher.renderView setInputRotation:previewMirror?kGPUImageFlipHorizonal:kGPUImageNoRotation atIndex:0];
}

-(void)setStreamMirror:(BOOL)streamMirror{
    _streamMirror = streamMirror;
    _publlisher.localCamera.streamMirror = streamMirror;
}

-(void)setCameraPosition:(AVCaptureDevicePosition)cameraPosition{
    _cameraPosition = cameraPosition;
    _publlisher.localCamera.cameraPosition = cameraPosition;
}

-(void)updateJanusWithServer:(NSURL*)server{
    if (![_janus.server.absoluteString isEqualToString:server.absoluteString]) {
        [_janus destorySession];
        _janus = [[GJJanus alloc]initWithServer:server delegate:self];
    }
}

-(void)joinRoomWithRoomID:(NSString *)roomID display:(NSString *)display appId:(NSString *)appId token:(NSString *)token completeCallback:(CompleteCallback)callback{
    AUTO_LOCK(_lock)
    _roomID = roomID;
    _display = display;
    
    WK_SELF;
    [_publlisher joinRoomWithRoomID:roomID display:display appId:appId token:token block:^(NSError *error) {
        if (callback) {
            callback(error == nil,error);
        }else{
            dispatch_async(dispatch_get_main_queue(), ^{
                [wkSelf.delegate GJJanusVideoRoom:wkSelf didJoinRoomWithID:wkSelf.publlisher.roomID];

            });
        }
    }];
}

-(void)leaveRoom:(void(^_Nullable )(void))leaveBlock{
    AUTO_LOCK(_lock)
    WK_SELF;
    for (GJJanusSubscriberRole *subscriberRole  in _remotes.allValues) {
        [subscriberRole leaveRoom:nil];
    }
    [_remotes removeAllObjects];
    [_publlisher leaveRoom:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (leaveBlock) {
                leaveBlock();
            }else{
                [wkSelf.delegate GJJanusVideoRoomDidLeaveRoom:wkSelf];
            }
        });

    }];
    
}

- (BOOL)startStickerWithImages:(NSArray<GJOverlayAttribute*>* _Nonnull)images fps:(NSInteger)fps updateBlock:(OverlaysUpdate _Nullable )updateBlock{

    return [_publlisher.localCamera startStickerWithImages:images fps:fps updateBlock:updateBlock];
}

- (void)chanceSticker{
    [_publlisher.localCamera chanceSticker];
}

-(void)setOutOrientation:(UIInterfaceOrientation)outOrientation{
    _publlisher.localCamera.outputOrientation = outOrientation;
}
-(UIInterfaceOrientation)outOrientation{
    return _publlisher.localCamera.outputOrientation;
}

-(void)setLocalConfig:(GJJanusPushlishMediaConstraints *)localConfig{
    AUTO_LOCK(_lock)
    
    [_publlisher setMediaConstraints:localConfig];

}

-(GJJanusPushlishMediaConstraints *)localConfig{
    AUTO_LOCK(_lock)
    return _publlisher.mediaConstraints;
}

-(BOOL)startPrewViewWithCanvas:(KKRTCCanvas*)canvas{
    AUTO_LOCK(_lock)
    NSAssert(canvas != nil && canvas.view != nil, @"param error");
    if ([canvas.uid isEqualToString:_publlisher.ID]) {
        [_publlisher startPreview];
        _publlisher.renderView.frame = canvas.view.bounds;
        _publlisher.renderView.frame = canvas.view.bounds;
        canvas.renderView = _publlisher.renderView;
        switch (canvas.renderMode) {
            case KKRTC_Render_Hidden:
                canvas.renderView.contentMode = UIViewContentModeScaleAspectFill;
                break;
            case KKRTC_Render_Fit:
                canvas.renderView.contentMode = UIViewContentModeScaleAspectFit;
            case KKRTC_Render_Fill:
                canvas.renderView.contentMode = UIViewContentModeScaleToFill;
            default:
                break;
        }
        [canvas.view addSubview:self.publlisher.renderView];
    }else{
        runAsyncInMainDispatch(^{
            GJJanusSubscriberRole* role = _remotes[canvas.uid];
            [role.renderView removeFromSuperview];
            role.renderView.frame = canvas.view.bounds;
            [canvas.view addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:(__bridge void * _Nullable)(canvas)];
            [canvas.view addSubview:role.renderView];
            canvas.renderView = role.renderView;
        });
    }
    _canvas[canvas.uid] = canvas;
    return YES;
}

-(KKRTCCanvas*)stopPrewViewWithUid:(NSString *)uid{
    AUTO_LOCK(_lock)
//    NSLog(@"%lu",(unsigned long)uid);
    KKRTCCanvas* canvas = _canvas[uid];
    if (uid == nil || [uid isEqualToString:_publlisher.ID]) {
        [_publlisher stopPreview];
    }else{
        GJJanusSubscriberRole* role = _remotes[canvas.uid];
        [canvas.view removeObserver:self forKeyPath:@"frame"];
        role.renderView = nil;
        [_canvas removeObjectForKey:uid];
    }
    return canvas;
}

- (void)startSubscriberRoleRemote:(GJJanusSubscriberRole*)remoteRole{
    AUTO_LOCK(_lock)
    NSLog(@"%s", remoteRole.description.UTF8String);
    _remotes[remoteRole.ID] = remoteRole;
    WK_SELF;
    [remoteRole joinRoomWithRoomID:wkSelf.roomID display:remoteRole.display appId:remoteRole.appID token:remoteRole.token block:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [wkSelf.delegate GJJanusVideoRoom:wkSelf newRemoteJoinWithID:remoteRole.ID];
        });
    }];
}

-(void)stopSubscriberRemote:(GJJanusSubscriberRole*)remoteRole{
    AUTO_LOCK(_lock)
    NSLog(@"%s", remoteRole.description.UTF8String);
    [_remotes removeObjectForKey:remoteRole.ID];
}


-(BOOL)prepareVideoEffectWithBaseData:(NSString *)baseDataPath{
    return [_publlisher.localCamera prepareVideoEffectWithBaseData:baseDataPath];
}
-(void)chanceVideoEffect{
    [_publlisher.localCamera chanceVideoEffect];
}

-(BOOL)updateFaceStickerWithTemplatePath:(NSString *)path{
    return [_publlisher.localCamera updateFaceStickerWithTemplatePath:path];
}

-(void)setSkinRuddy:(NSInteger)skinRuddy{
    _publlisher.localCamera.skinRuddy = skinRuddy;
}
-(NSInteger)skinRuddy{
    return _publlisher.localCamera.skinRuddy;
}

-(void)setSkinSoften:(NSInteger)skinSoften{
    _publlisher.localCamera.skinSoften = skinSoften;
}
-(NSInteger)skinSoften{
    return _publlisher.localCamera.skinSoften;
}

-(void)setSkinBright:(NSInteger)skinBright{
    _publlisher.localCamera.skinBright = skinBright;
}
-(NSInteger)skinBright{
    return _publlisher.localCamera.skinBright;
}

-(void)setEyeEnlargement:(NSInteger)eyeEnlargement{
    _publlisher.localCamera.eyeEnlargement = eyeEnlargement;
}
-(NSInteger)eyeEnlargement{
    return _publlisher.localCamera.eyeEnlargement;
}

-(void)setFaceSlender:(NSInteger)faceSlender{
    _publlisher.localCamera.faceSlender = faceSlender;
}
-(NSInteger)faceSlender{
    return _publlisher.localCamera.faceSlender;
}

#pragma mark delegate

-(void)janus:(GJJanus *)janus createComplete:(NSError *)error{
    AUTO_LOCK(_lock)
    NSAssert(error == nil, error.description);
    if (error == nil) {
        WK_SELF;
        dispatch_async(dispatch_get_main_queue(), ^{
            if(error){
//                GJLOG(GNULL, GJ_LOGERROR, "attachToJanus error:%s",error.description.UTF8String);
                [wkSelf.delegate GJJanusVideoRoom:wkSelf fatalErrorWithID:KKRTCError_Server_Error];
            }
        });
    }else{
        dispatch_async(dispatch_get_main_queue(), ^{
//            GJLOG(GNULL, GJ_LOGERROR, "createComplete error:%s",error.description.UTF8String);
            [self.delegate GJJanusVideoRoom:self fatalErrorWithID:KKRTCError_Server_Error];
        });
    }
}

-(void)janusDestory:(GJJanus*)janus{
    NSLog(@"%s", janus.description.UTF8String);
}

-(void)GJJanusRole:(GJJanusRole *)role joinRoomWithResult:(NSError *)error{
    AUTO_LOCK(_lock)
    NSAssert(error == nil, error.description);
    if ([role.ID isEqualToString:_publlisher.ID]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate GJJanusVideoRoom:self didJoinRoomWithID:role.ID];
        });
    }else{
        assert(0);
    }
}

-(void)GJJanusRole:(GJJanusRole*)role leaveRoomWithResult:(NSError*)error{
    AUTO_LOCK(_lock)
    NSAssert(error == nil, error.description);
    if ([role.ID isEqualToString:_publlisher.ID]) {
        [self.janus destorySession];
    }
}

- (void)GJJanusRole:(GJJanusRole *)role didJoinRemoteRole:(GJJanusSubscriberRole *)remoteRole {
    AUTO_LOCK(_lock)
    NSLog(@"%s", remoteRole.description.UTF8String);
    for (GJJanusRole* remote in _remotes.allValues) {
        if ([remote.ID isEqualToString:remoteRole.ID]) {
            return;
        }
    }
    [self startSubscriberRoleRemote:remoteRole];
}
-(void)GJJanusRole:(GJJanusRole *)role remoteUnPublishedWithUid:(NSString *)uid{
    
}

- (void)GJJanusRole:(GJJanusRole *)role didLeaveRemoteRoleWithUid:(NSString *)uid{
    AUTO_LOCK(_lock)
    NSLog(@"%lu",(unsigned long)uid);
    GJJanusSubscriberRole* leaveRole = _remotes[uid];
    if (leaveRole) {
        [_remotes removeObjectForKey:uid];
        [leaveRole detachWithCallback:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate GJJanusVideoRoom:self remoteLeaveWithID:uid];
        });
    }
}

-(void)GJJanusRole:(GJJanusRole *)role remoteDetachWithUid:(NSString *)uid{
    AUTO_LOCK(_lock)
    NSLog(@"%lu",(unsigned long)uid);
    GJJanusSubscriberRole* leaveRole = _remotes[uid];
    if (leaveRole) {
        [_remotes removeObjectForKey:uid];
        [role detachWithCallback:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate GJJanusVideoRoom:self remoteLeaveWithID:uid];
        });
    }
}

-(void)janusSubscriberRole:(GJJanusSubscriberRole *)role firstRenderWithSize:(CGSize)size{
    runAsyncInMainDispatch(^{
        if ([self.delegate respondsToSelector:@selector(GJJanusVideoRoom:firstFrameDecodeWithSize:uid:)]) {
            [self.delegate GJJanusVideoRoom:self firstFrameDecodeWithSize:size uid:role.ID];
        }
    });
}

-(void)janusSubscriberRole:(GJJanusSubscriberRole *)role renderSizeChangeWithSize:(CGSize)size{
    runAsyncInMainDispatch(^{
        if ([self.delegate respondsToSelector:@selector(GJJanusVideoRoom:renderSizeChangeWithSize:uid:)]) {
            [self.delegate GJJanusVideoRoom:self renderSizeChangeWithSize:size uid:role.ID];
        }
    });
}

-(void)janus:(GJJanus *)janus netBrokenWithID:(KKRTCNetBrokenReason)reason{
    [self leaveRoom:nil];
    runAsyncInMainDispatch(^{
        [self.delegate GJJanusVideoRoom:self netBrokenWithID:reason];
    });
}

- (void)janus:(GJJanus *)janus attachPlugin:(NSNumber *)handleID result:(NSError *)error {
    NSLog(@"%s",__FUNCTION__);
}


-(void)updateRenderViewFrame:(KKRTCCanvas*)canvas{
    canvas.renderView.frame = canvas.view.bounds;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    if ([keyPath isEqualToString:@"frame"]) {
        KKRTCCanvas* canvas = (__bridge KKRTCCanvas *)(context);
        [self updateRenderViewFrame:canvas];
    }
}
-(void)dealloc{
    [self.janus destorySession];
}

@end

