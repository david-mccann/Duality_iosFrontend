//  Created by David McCann on 5/9/16.
//  Copyright © 2016 Scientific Computing and Imaging Institute. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Render2DViewController.h"
#import "DynamicUIBuilder.h"
#import "SettingsObject.h"

#include "src/IVDA/iOS.h"
#include "src/IVDA/GLInclude.h"
#include "duality/ScreenInfo.h"

@implementation Render2DViewController

@synthesize context = _context;

-(void) setSceneController:(std::shared_ptr<SceneController2D>)controller
{
    m_sceneController = controller;
}

- (ScreenInfo)screenInfo
{
    float scale = iOS::DetectScreenScale();
    float iPad = iOS::DetectIPad() ? 2 : 1;
    float xOffset = 0.0f;
    float yOffset = 0.0f;
    float windowWidth = 1.0f;
    float windowHeight = 1.0f;
    unsigned int width = scale * self.view.bounds.size.width;
    unsigned int height = scale * self.view.bounds.size.height;
    ScreenInfo screenInfo(width, height, xOffset, yOffset,
                          /*m_pSettings->getUseRetinaResolution() ? 1.0 : fScale*/ scale, iPad * scale * 2, windowWidth, windowHeight);
    return screenInfo;
}

- (void)initGL
{
    [EAGLContext setCurrentContext:self.context];
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    view.multipleTouchEnabled = YES;
    
    GL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));
    GL(glClearColor(0.0f, 0.0f, 0.0f, 1.0f));
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self initGL];
    
    m_sliceSelector = [[UISlider alloc] init];
    m_sliceSelector.alpha = 0.8;
    [m_sliceSelector addTarget:self action:@selector(setSlice) forControlEvents:UIControlEventValueChanged];
    m_sliceSelector.backgroundColor = [UIColor clearColor];
    CGAffineTransform trans = CGAffineTransformMakeRotation(M_PI * 0.5);
    m_sliceSelector.transform = trans;
    m_sliceSelector.frame = CGRectMake(self.view.frame.size.width - 60, 50, 50, self.view.frame.size.height - 100);
    
    m_sliceLabel = [[UITextView alloc] init];
    [m_sliceLabel setFont:[UIFont boldSystemFontOfSize:12]];
    [m_sliceLabel setEditable:NO];
    [m_sliceLabel setTextColor:[UIColor whiteColor]];
    [m_sliceLabel setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.8]];
    [m_sliceLabel setTextAlignment:NSTextAlignmentCenter];
    [m_sliceLabel setUserInteractionEnabled:NO];
    m_sliceLabel.frame = CGRectMake(self.view.frame.size.width - 180, 174, 120, 40);
    
    m_toggleAxisButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [m_toggleAxisButton addTarget:self action:@selector(toggleAxis) forControlEvents:UIControlEventTouchDown];
    [m_toggleAxisButton setTitleColor:m_toggleAxisButton.tintColor forState:UIControlStateNormal];
    [m_toggleAxisButton setBackgroundColor:[UIColor colorWithWhite:1 alpha:0.8]];
    [m_toggleAxisButton.titleLabel setFont:[UIFont boldSystemFontOfSize:12]];
    m_toggleAxisButton.frame = CGRectMake(self.view.frame.size.width - 180, 50, 120, 40);
    
    [self.view addSubview:m_sliceSelector];
    [self.view addSubview:m_sliceLabel];
    [self.view addSubview:m_toggleAxisButton];
    
    // when the application resumes from background, we need to force a redraw, even though no rendering parameters changed
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(redrawGL) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    m_numFingersDown = 0;
}

-(void) setup
{
    if (m_sceneController != nullptr) {
        try {
            m_sceneController->updateScreenInfo([self screenInfo]);
            
            auto variableMap = m_sceneController->variableMap();
            if (!variableMap.empty()) {
                m_dynamicUI = buildStackViewFromVariableMap(variableMap,
                    [=](std::string objectName, std::string variableName, float value) {
                        m_sceneController->setVariable(objectName, variableName, value);
                    },
                    [=](std::string objectName, std::string variableName, std::string value) {
                        m_sceneController->setVariable(objectName, variableName, value);
                    },
                    [=](std::string nodeName, bool enabled) {
                        m_sceneController->setNodeUpdateEnabled(nodeName, enabled);
                    });
                m_dynamicUI.translatesAutoresizingMaskIntoConstraints = false;
                [self.view addSubview:m_dynamicUI];
                [m_dynamicUI.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:20.0].active = true;
                [m_dynamicUI.leftAnchor constraintEqualToAnchor:self.view.leftAnchor constant:20.0].active = true;
            }
            
            if (m_sceneController->supportsSlices()) {
                auto numSlices = m_sceneController->numSlicesForCurrentAxis();
                m_sliceSelector.minimumValue = 0;
                m_sliceSelector.maximumValue = numSlices;
                m_sliceSelector.value = m_sceneController->sliderParameter().slice();
                m_sliceLabel.text = [NSString stringWithFormat:@"%i", m_sceneController->sliderParameter().slice()];
            } else {
                auto minMaxForAxis = m_sceneController->boundsForCurrentAxis();
                m_sliceSelector.minimumValue = minMaxForAxis.first;
                m_sliceSelector.maximumValue = minMaxForAxis.second;
                m_sliceSelector.value = m_sceneController->sliderParameter().depth();
                m_sliceLabel.text = [NSString stringWithFormat:@"%.4f", m_sliceSelector.value];
            }
            
            SceneController2D::AxisLabelMode mode = m_sceneController->settings()->anatomicalTerms()
                ? SceneController2D::AxisLabelMode::Anatomical
                : SceneController2D::AxisLabelMode::Mathematical;
            NSString* axisLabel = [NSString stringWithUTF8String:m_sceneController->labelForCurrentAxis(mode).c_str()];
            [m_toggleAxisButton setTitle:axisLabel forState:UIControlStateNormal];
            
            // unhide widgets after everything else has been setup successfully
            [m_sliceSelector setHidden:false];
            [m_sliceLabel setHidden:false];
            [m_toggleAxisButton setHidden:false];
            
            m_sceneController->setRedrawRequired();

        }
        catch(const std::exception& err) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ErrorOccured" object:nil userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:err.what()], @"Error", nil]];
        }
    }
}

-(void) reset
{
    m_sceneController = nullptr;
    [m_sliceSelector setHidden:true];
    [m_sliceLabel setHidden:true];
    [m_toggleAxisButton setHidden:true];

    if (m_dynamicUI) {
        [m_dynamicUI removeFromSuperview];
    }
    
    glClear(GL_COLOR_BUFFER_BIT);
}

-(void) redrawGL
{
    if (m_sceneController != nullptr) {
        m_sceneController->setRedrawRequired();
    }
}

-(void) setSlice
{
    if (m_sceneController->supportsSlices()) {
        int slice = std::min<int>(roundf(m_sliceSelector.value), m_sceneController->numSlicesForCurrentAxis() - 1);
        m_sceneController->setSlice(slice);
        m_sliceLabel.text = [NSString stringWithFormat:@"%i", slice];
    }else {
        m_sceneController->setDepth(m_sliceSelector.value);
        m_sliceLabel.text = [NSString stringWithFormat:@"%.4f", m_sliceSelector.value];
    }
}

-(void) toggleAxis
{
    m_sceneController->toggleAxis();

    // set slice to value that corresponds to the current slider position
    const float oldMin = m_sliceSelector.minimumValue;
    const float oldMax = m_sliceSelector.maximumValue;
    const float oldDistance = oldMax - oldMin;
    const float oldRelValue = m_sliceSelector.value - oldMin;
    const float epsilon = 0.000001f;
    const float amount = oldRelValue / oldDistance;
    if (m_sceneController->supportsSlices()) {
        auto numSlices = m_sceneController->numSlicesForCurrentAxis();
        int slice = std::min<int>(roundf(amount * numSlices), numSlices - 1);
        m_sliceSelector.minimumValue = 0;
        m_sliceSelector.maximumValue = numSlices;
        m_sliceSelector.value = slice;
        m_sliceLabel.text = [NSString stringWithFormat:@"%i", slice];
        m_sceneController->setSlice(slice);
    } else {
        const auto minMaxForAxis = m_sceneController->boundsForCurrentAxis();
        m_sliceSelector.minimumValue = minMaxForAxis.first;
        m_sliceSelector.maximumValue = minMaxForAxis.second;
        const float newDistance = minMaxForAxis.second - minMaxForAxis.first;
        if (std::abs(oldDistance) > epsilon && std::abs(newDistance) > epsilon) {
            m_sliceSelector.value = (amount * newDistance) + minMaxForAxis.first;
            m_sliceLabel.text = [NSString stringWithFormat:@"%.4f", m_sliceSelector.value];
            m_sceneController->setDepth(m_sliceSelector.value);
        }
    }

    SceneController2D::AxisLabelMode mode = [[NSUserDefaults standardUserDefaults] boolForKey:@"AnatomicalTerms"] ? SceneController2D::AxisLabelMode::Anatomical : SceneController2D::AxisLabelMode::Mathematical;
    NSString* axisLabel = [NSString stringWithUTF8String:m_sceneController->labelForCurrentAxis(mode).c_str()];
    [m_toggleAxisButton setTitle:axisLabel forState:UIControlStateNormal];
}

// Drawing
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    if (m_sceneController != nullptr) {
        m_sceneController->render();
    }
    [view bindDrawable];
}

// Interaction
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    if (m_sceneController == nullptr) {
        return;
    }
    
    NSUInteger numTouches = [[event allTouches] count];
    if (m_numFingersDown > numTouches) {
        // this prevents the scene from "jumping" when a two-finger action was performed and one finger is lifted
        return;
    }
    if (numTouches == 1) {
        CGPoint touchPoint = [[touches anyObject] locationInView:self.view];
        m_touchPos1 = IVDA::Vec2f(touchPoint.x/self.view.frame.size.width,
                                  touchPoint.y/self.view.frame.size.height);
    }
    else if (numTouches == 2) {
        NSArray* allTouches = [[event allTouches] allObjects];
        CGPoint touchPoint1 = [[allTouches objectAtIndex:0] locationInView:self.view];
        CGPoint touchPoint2 = [[allTouches objectAtIndex:1] locationInView:self.view];
        m_touchPos1 = IVDA::Vec2f(touchPoint1.x/self.view.frame.size.width,
                                  touchPoint1.y/self.view.frame.size.height);
        m_touchPos2 = IVDA::Vec2f(touchPoint2.x/self.view.frame.size.width,
                                  touchPoint2.y/self.view.frame.size.height);
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    if (m_sceneController == nullptr) {
        return;
    }
    
    UITouch* touch = [[event touchesForView:self.view] anyObject];
    CGPoint pos = [touch locationInView:self.view];
    CGPoint prev = [touch previousLocationInView:self.view];
    NSUInteger numTouches = [[event allTouches] count];
    if (m_numFingersDown > numTouches) {
        // this prevents the scene from "jumping" when a two-finger action was performed and one finger is lifted
        return;
    }
    
    if (pos.x == prev.x && pos.y == prev.y && numTouches == 1) {
        return;
    }
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    if (numTouches == 1) {
        CGPoint touchPoint = [[touches anyObject] locationInView:self.view];
        IVDA::Vec2f touchPos(touchPoint.x/self.view.frame.size.width,
                             touchPoint.y/self.view.frame.size.height);
        
        [self transformOneTouch:touchPos];
        
        m_touchPos1 = touchPos;
    }
    else if (numTouches == 2) {
        NSArray* allTouches = [[event allTouches] allObjects];
        CGPoint touchPoint1 = [[allTouches objectAtIndex:0] locationInView:self.view];
        CGPoint touchPoint2 = [[allTouches objectAtIndex:1] locationInView:self.view];
        
        IVDA::Vec2f touchPos1(touchPoint1.x/self.view.frame.size.width,
                              touchPoint1.y/self.view.frame.size.height);
        IVDA::Vec2f touchPos2(touchPoint2.x/self.view.frame.size.width,
                              touchPoint2.y/self.view.frame.size.height);
        
        [self transformTwoTouch:touchPos1 andWith:touchPos2];
        
        m_touchPos1 = touchPos1;
        m_touchPos2 = touchPos2;
    }
}

-(void) touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    m_numFingersDown = [[event allTouches] count];
}

-(void) transformOneTouch:(const IVDA::Vec2f&)touchPos
{
    IVDA::Vec2f translation(touchPos.x - m_touchPos1.x, -(touchPos.y - m_touchPos1.y));
    m_sceneController->addTranslation(translation);
    m_touchPos1 = touchPos;
}

- (void) transformTwoTouch:(const IVDA::Vec2f&)touchPos1 andWith:(const IVDA::Vec2f&)touchPos2
{
    IVDA::Vec2f d1(m_touchPos1.x - m_touchPos2.x, m_touchPos1.y - m_touchPos2.y);
    IVDA::Vec2f d2(touchPos1.x - touchPos2.x, touchPos1.y - touchPos2.y);
    float l1 = d1.length();
    float l2 = d2.length();
    m_sceneController->addZoom(l2-l1);
    
    float angle = 0;
    if (l1 > 0 && l2 > 0) {
        d1 /= l1;
        d2 /= l2;
        angle = atan2(d1.y,d1.x) - atan2(d2.y,d2.x);
    }
    m_sceneController->addRotation(angle);
}

@end
