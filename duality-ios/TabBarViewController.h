//  Created by David McCann on 5/4/16.
//  Copyright © 2016 Scientific Computing and Imaging Institute. All rights reserved.
//

#import "SelectSceneViewController.h"
#import "SettingsViewController.h"
#import "Render3DViewController.h"
#import "Render2DViewController.h"

#import <UIKit/UIKit.h>
#import <SafariServices/SFSafariViewController.h>

class SceneLoader;

@interface TabBarViewController : UITabBarController<UITabBarControllerDelegate> {
@private
    std::unique_ptr<SceneLoader> m_sceneLoader;
    Render3DViewController* m_render3DViewController;
    Render2DViewController* m_render2DViewController;
    SelectSceneViewController* m_selectSceneViewController;
    SettingsViewController* m_settingsViewController;
    SFSafariViewController* m_webViewController;
    
    UILabel* m_loadingLabel;
    UILabel* m_progressLabel;
    UIProgressView* m_progress;
}

- (id)init;

@end
