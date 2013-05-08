//
// UIScrollView+BalloonPullToRefresh.m
// Balloon Pull Demo
//
//  Created by Dmitry Klimkin on 5/5/13.
//  Copyright (c) 2013 Dmitry Klimkin. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "UIScrollView+BalloonPullToRefresh.h"

#define ScreenWidth  [[UIScreen mainScreen] bounds].size.width
#define ScreenHeight [[UIScreen mainScreen] bounds].size.height

#define BalloonPullToRefreshViewHeight 300
#define BalloonPullToRefreshViewTriggerAreaHeight 101
#define BalloonPullToRefreshViewParticleSize 0.5
#define BalloonPullToRefreshViewAnimationRadius 35.0
#define BalloonPullToRefreshViewParticlesCount 8
#define BalloonPullToRefreshViewAnimationAngle (360.0 / self.particlesCount)

@interface BalloonPullToRefreshView ()

@property (nonatomic, copy) void (^pullToRefreshActionHandler)(void);
@property (nonatomic, readwrite) BalloonPullToRefreshState currentState;
@property (nonatomic, weak) UIScrollView *scrollView;
@property (nonatomic, readwrite) CGFloat originalTopInset;
@property (nonatomic, assign) BOOL wasTriggeredByUser;
@property (nonatomic, assign) BOOL showsPullToRefresh;
@property (nonatomic, assign) BOOL isObserving;
@property (nonatomic, strong) NSArray *particles;

- (void)resetScrollViewContentInset;
- (void)setScrollViewContentInsetForLoading;
- (void)setScrollViewContentInset:(UIEdgeInsets)insets;

@end

#pragma mark - UIScrollView (BalloonPullToRefresh)
#import <objc/runtime.h>

static char UIScrollViewPullToRefreshView;

@implementation UIScrollView (BalloonPullToRefresh)

@dynamic pullToRefreshController, showsPullToRefresh;

- (void)addPullToRefreshWithActionHandler:(void (^)(void))actionHandler {
    
    if (!self.pullToRefreshController) {
        BalloonPullToRefreshView *view = [[BalloonPullToRefreshView alloc] initWithFrame:CGRectMake(0, -BalloonPullToRefreshViewHeight, self.bounds.size.width, BalloonPullToRefreshViewHeight)];
        view.pullToRefreshActionHandler = actionHandler;
        view.scrollView = self;
        
        [self addSubview:view];
        
        view.originalTopInset = self.contentInset.top;
        self.pullToRefreshController = view;
        self.showsPullToRefresh = YES;
    }
}

- (void)triggerPullToRefresh {
    self.pullToRefreshController.currentState = BalloonPullToRefreshStateTriggered;
    [self.pullToRefreshController startAnimating];
}

- (void)setPullToRefreshController:(BalloonPullToRefreshView *)pullToRefreshView {
    [self willChangeValueForKey:@"BalloonPullToRefreshView"];
    objc_setAssociatedObject(self, &UIScrollViewPullToRefreshView,
                             pullToRefreshView,
                             OBJC_ASSOCIATION_ASSIGN);
    [self didChangeValueForKey:@"BalloonPullToRefreshView"];
}

- (BalloonPullToRefreshView *)pullToRefreshController {
    return objc_getAssociatedObject(self, &UIScrollViewPullToRefreshView);
}

- (void)setShowsPullToRefresh:(BOOL)showsPullToRefresh {
    self.pullToRefreshController.hidden = !showsPullToRefresh;
    
    if (!showsPullToRefresh) {
        if (self.pullToRefreshController.isObserving) {
            
            [self removeObserver:self.pullToRefreshController forKeyPath:@"contentOffset"];
            [self removeObserver:self.pullToRefreshController forKeyPath:@"frame"];
            [self.pullToRefreshController resetScrollViewContentInset];
            
            self.pullToRefreshController.isObserving = NO;
        }
    }
    else if (!self.pullToRefreshController.isObserving) {
        [self addObserver:self.pullToRefreshController forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil];
        [self addObserver:self.pullToRefreshController forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
        
        self.pullToRefreshController.isObserving = YES;
    }
}

- (BOOL)showsPullToRefresh {
    return !self.pullToRefreshController.hidden;
}

@end

#pragma mark - BalloonPullToRefresh
@implementation BalloonPullToRefreshView

// public properties
@synthesize pullToRefreshActionHandler;

@synthesize currentState = _state;
@synthesize scrollView = _scrollView;
@synthesize showsPullToRefresh = _showsPullToRefresh;
@synthesize particles = _particles;
@synthesize waitingAnimation = _waitingAnimation;
@synthesize particlesCount = _particlesCount;

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        
        // default styling values
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.currentState = BalloonPullToRefreshStateStopped;
        
        self.backgroundColor = [UIColor colorWithRed:0.65f green:0.83f blue:0.93f alpha:1.00f];
        self.clipsToBounds = YES;
        self.particlesCount = BalloonPullToRefreshViewParticlesCount;        
    }

    return self;
}

- (void) setParticlesCount:(int)particlesCount {
    
    for (int i=0; i<self.particles.count; i++) {
        UIView *particleView = self.particles [i];
        [particleView removeFromSuperview];
    }
    
    _particlesCount = particlesCount;
    
    NSMutableArray *particles = [NSMutableArray new];
    NSArray *images = @[@"circle_blue", @"circle_red", @"circle_green", @"circle_orange", @"circle_purple", @"circle_seagreen"];
    
    for (int i=0; i<self.particlesCount; i++) {
        UIImageView *particleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed: images[i % images.count]]];
        
        particleView.alpha = 0.5;
        particleView.backgroundColor = [UIColor clearColor];
        particleView.frame = CGRectMake(0, 0, BalloonPullToRefreshViewParticleSize, BalloonPullToRefreshViewParticleSize);
        
        // Optionally:
        //[self setCornerForView: particleView];
        
        [self addSubview: particleView];
        [particles addObject: particleView];
    }
    _particles = particles;    
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    if (self.superview && newSuperview == nil) {
        //use self.superview, not self.scrollView. Why self.scrollView == nil here?
        UIScrollView *scrollView = (UIScrollView *)self.superview;
        if (scrollView.showsPullToRefresh) {
            if (self.isObserving) {
                //If enter this branch, it is the moment just before "BalloonPullToRefreshView's dealloc", so remove observer here
                [scrollView removeObserver:self forKeyPath:@"contentOffset"];
                [scrollView removeObserver:self forKeyPath:@"frame"];
                
                self.isObserving = NO;
            }
        }
    }
}

#pragma mark - Scroll View

- (void)resetScrollViewContentInset {
    UIEdgeInsets currentInsets = self.scrollView.contentInset;
    currentInsets.top = self.originalTopInset;
    [self setScrollViewContentInset:currentInsets];
}

- (void)setScrollViewContentInsetForLoading {
    UIEdgeInsets currentInsets = self.scrollView.contentInset;
    currentInsets.top = BalloonPullToRefreshViewTriggerAreaHeight;
        
    [self setScrollViewContentInset:currentInsets];
}

- (void)setScrollViewContentInset:(UIEdgeInsets)contentInset {
    [UIView animateWithDuration:0.3
                          delay:0
                        options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.scrollView.contentInset = contentInset;
                         self.scrollView.contentOffset = CGPointMake(0, 0);
                     }
                     completion:nil];
}

#pragma mark - Observing

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"contentOffset"]) {
        
        CGPoint oldOffset = [[change objectForKey:NSKeyValueChangeOldKey] CGPointValue];
        
        [self contentOffsetChanged: oldOffset.y];
        [self scrollViewDidScroll:[[change valueForKey:NSKeyValueChangeNewKey] CGPointValue]];
    } else {
        if ([keyPath isEqualToString:@"frame"]) {
            [self layoutSubviews];
        }
    }
}

- (void)scrollViewDidScroll:(CGPoint)contentOffset {
    if (self.currentState != BalloonPullToRefreshStateLoading) {
        
        CGFloat scrollOffsetThreshold = self.frame.origin.y-self.originalTopInset;

        if (!self.scrollView.isDragging && self.currentState == BalloonPullToRefreshStateTriggered) {
            self.currentState = BalloonPullToRefreshStateLoading;
        }
        else if (((contentOffset.y < scrollOffsetThreshold) || (contentOffset.y < -BalloonPullToRefreshViewTriggerAreaHeight)) && self.scrollView.isDragging && self.currentState == BalloonPullToRefreshStateStopped) {
            self.currentState = BalloonPullToRefreshStateTriggered;
        }
        else if (contentOffset.y >= scrollOffsetThreshold && self.currentState != BalloonPullToRefreshStateStopped) {
            self.currentState = BalloonPullToRefreshStateStopped;
        }
    }
}

- (void)triggerRefresh {
    [self.scrollView triggerPullToRefresh];    
}

- (void)doSpinAnimationStepForWaitingAnimation {
    animationStep ++;
    
    for (int i=0; i<self.particles.count; i++) {
 
        float angle = - (i * BalloonPullToRefreshViewAnimationAngle + animationStep * 5) * M_PI / 180;
        float radius = BalloonPullToRefreshViewAnimationRadius;
        
        UIView *particleView = self.particles [i];

        particleView.center = CGPointMake((ScreenWidth / 2) + radius * cos (angle), self.frame.size.height - ((BalloonPullToRefreshViewTriggerAreaHeight / 2) + radius * sin(angle)));
    }
}

- (void)doFadeAnimationStepForWaitingAnimation {
    
    int prevAnimationStep = animationStep;
    
    animationStep = (animationStep + 1) % self.particles.count;
    
    [self animateAlphaForView:self.particles[prevAnimationStep] newAlpha:0.3];
    [self animateAlphaForView:self.particles[animationStep] newAlpha:0.8];
}

- (void)onAnimationTimer {
    
    if (isRefreshing) {
        if (self.waitingAnimation == BalloonPullToRefreshWaitAnimationSpin) {
            [self doSpinAnimationStepForWaitingAnimation];
        } else {
            [self doFadeAnimationStepForWaitingAnimation];
        }
    } else {
        if (lastOffset < 30) {
            [animationTimer invalidate];
            animationTimer = nil;
            
            self.currentState = BalloonPullToRefreshStateStopped;
            
            if (!self.wasTriggeredByUser) {
                [self.scrollView setContentOffset:CGPointMake(self.scrollView.contentOffset.x, 0) animated:YES];
            }
            
            return;
        }
        
        lastOffset -= 2;
        
        [self contentOffsetChanged:-lastOffset];
    }
}

- (void)animateAlphaForView: (UIView *)viewToAnimate newAlpha: (float)newAlpha {
    [UIView animateWithDuration:0.3
                          delay:0.0
                        options: UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         viewToAnimate.alpha = newAlpha;
                     }
                     completion:^(BOOL finished){
                     }];
}

- (void)startAnimating {
    if (self.scrollView.contentOffset.y == 0) {
        [self.scrollView setContentOffset:CGPointMake(self.scrollView.contentOffset.x, -BalloonPullToRefreshViewTriggerAreaHeight) animated:YES];
        self.wasTriggeredByUser = NO;
    }
    else
        self.wasTriggeredByUser = YES;
    
    self.currentState = BalloonPullToRefreshStateLoading;
    
    [animationTimer invalidate];
    animationTimer = nil;
    
    isRefreshing = YES;
    animationStep = 0;
    
    [UIView animateWithDuration:0.3
                          delay:0.2
                        options: UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         for (int i=0; i<self.particles.count; i++) {
                             float angle = - (i * BalloonPullToRefreshViewAnimationAngle) * M_PI / 180;
                             float radius = BalloonPullToRefreshViewAnimationRadius;
                             
                             UIView *particleView = self.particles [i];
                             
                             particleView.center = CGPointMake((ScreenWidth / 2) + radius * cos (angle), self.frame.size.height - ((BalloonPullToRefreshViewTriggerAreaHeight / 2) + radius * sin(angle)));
                         }
                     }
                     completion:^(BOOL finished){
                         if (finished) {
                             float timeInterval = 0.02;
                             
                             if (self.waitingAnimation == BalloonPullToRefreshWaitAnimationFade) {
                                 timeInterval = 0.2;
                             }
                             
                             animationTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(onAnimationTimer) userInfo:nil repeats:YES];
                         }
                     }];
}

- (void)didFinishRefresh {
    
    if (isRefreshing == NO) {
        return;
    }

    isRefreshing = NO;
    
    [self setNeedsDisplay];
    
    [animationTimer invalidate];
    animationTimer = nil;
    
    for (int i=0; i<self.particles.count; i++) {
        UIView *particleView = self.particles [i];
        
        particleView.alpha = 0.5;
    }
    
    animationTimer = [NSTimer scheduledTimerWithTimeInterval:0.01 target:self selector:@selector(onAnimationTimer) userInfo:nil repeats:YES];
}

- (void)setCurrentState:(BalloonPullToRefreshState)newState {
    
    if (_state == newState)
        return;
    
    BalloonPullToRefreshState previousState = _state;
    _state = newState;
    
    [self setNeedsLayout];
    
    switch (newState) {
        case BalloonPullToRefreshStateStopped:
            [self resetScrollViewContentInset];
            break;
            
        case BalloonPullToRefreshStateTriggered:
            [self startAnimating];
            break;
            
        case BalloonPullToRefreshStateLoading:
            [self setScrollViewContentInsetForLoading];
            
            if (previousState == BalloonPullToRefreshStateTriggered && pullToRefreshActionHandler)
                pullToRefreshActionHandler();
            break;
            
        default: break;
    }
}

- (void) contentOffsetChanged:(float)contentOffset {
    contentOffset = -contentOffset / 2;
        
    if (isRefreshing) {
        return;
    }
    
    if (contentOffset < -10) {
        contentOffset = -10;
    }
    
    if (contentOffset > BalloonPullToRefreshViewTriggerAreaHeight / 2) {
        contentOffset = BalloonPullToRefreshViewTriggerAreaHeight / 2;
    }
    
    lastOffset = contentOffset * 2;
    
    float ratio = (contentOffset / 2);
    
    if (contentOffset == BalloonPullToRefreshViewTriggerAreaHeight / 2) {
        for (int i=0; i<self.particles.count; i++) {
            UIView *particleView = self.particles [i];
            particleView.center = CGPointMake(ScreenWidth / 2, self.frame.size.height - contentOffset);
        }
    } else {
        for (int i=0; i<self.particles.count; i++) {
            
            float angle = - (i * BalloonPullToRefreshViewAnimationAngle + contentOffset) * M_PI / 180;
            float radius = 200 - (contentOffset * 4);
            
            UIView *particleView = self.particles [i];
            
            particleView.frame = CGRectMake(0, 0, BalloonPullToRefreshViewParticleSize + ratio, BalloonPullToRefreshViewParticleSize + ratio);
            particleView.center = CGPointMake((ScreenWidth / 2) + radius * cos (angle), self.frame.size.height - ((BalloonPullToRefreshViewTriggerAreaHeight / 2) + radius * sin(angle)));
        }
    }
    
    [self setNeedsDisplay];
}

-(void)setCornerForView: (UIView*)view {
    view.layer.shouldRasterize = YES;
    view.layer.rasterizationScale = [UIScreen mainScreen].scale;
    view.layer.cornerRadius = 10.0f;
    view.layer.masksToBounds = YES;
}

@end

