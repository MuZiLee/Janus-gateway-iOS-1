//
//  GJJanusSubscriberRole.h
//  GJJanus
//
//  Created by melot on 2018/4/3.
//  Copyright © 2018年 MirrorUncle. All rights reserved.
//

#import "GJJanusRole.h"
#import <WebRTC/RTCEAGLVideoView.h>
@class GJJanusSubscriberRole;
@protocol GJJanusSubscriberRoleDelegate<GJJanusRoleDelegate>
-(void)janusSubscriberRole:(GJJanusSubscriberRole *)role firstRenderWithSize:(CGSize)size;
-(void)janusSubscriberRole:(GJJanusSubscriberRole *)role renderSizeChangeWithSize:(CGSize)size;

@end
@interface GJJanusSubscriberRole : GJJanusRole<RTCEAGLVideoViewDelegate>
@property(nonatomic,retain)RTCEAGLVideoView *renderView;
@property(nonatomic,weak)id<GJJanusSubscriberRoleDelegate> delegate;
@end
