//
//  RootViewController.m
//  TerracottaHelper
//
//  Main menu: lets the user choose between Host mode, Guest mode,
//  Settings, and Instructions.
//

#import "RootViewController.h"
#import "HostViewController.h"
#import "GuestViewController.h"
#import "SettingsViewController.h"
#import "TerracottaBridge.h"
#import "TerracottaLog.h"

@interface RootViewController ()
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"陶瓦联机";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)setupUI {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:container];

    // App icon / title
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"陶瓦联机助手";
    titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = @"配合 Amethyst-iOS 使用，与 HMCL / FCL / ZL2 互通";
    subtitleLabel.font = [UIFont systemFontOfSize:14];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:subtitleLabel];

    // Buttons
    UIButton *hostBtn = [self makeButtonWithTitle:@"🏠  我是房主\n（开放我的世界给好友）"
                                           color:UIColor.systemBlueColor
                                          action:@selector(hostTapped)];
    UIButton *guestBtn = [self makeButtonWithTitle:@"🎮  我是房客\n（加入好友的房间）"
                                            color:UIColor.systemGreenColor
                                           action:@selector(guestTapped)];
    UIButton *settingsBtn = [self makeButtonWithTitle:@"⚙️  设置"
                                               color:UIColor.systemGrayColor
                                              action:@selector(settingsTapped)];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        titleLabel, subtitleLabel, hostBtn, guestBtn, settingsBtn
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 20;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                        constant:40],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                            constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                             constant:-24],
    ]];
}

- (UIButton *)makeButtonWithTitle:(NSString *)title
                            color:(UIColor *)color
                           action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.backgroundColor = color;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    btn.titleLabel.numberOfLines = 0;
    btn.titleLabel.textAlignment = NSTextAlignmentCenter;
    btn.layer.cornerRadius = 16;
    btn.layer.masksToBounds = YES;
    btn.contentEdgeInsets = UIEdgeInsetsMake(20, 16, 20, 16);
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn.heightAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
    return btn;
}

#pragma mark - Actions

- (void)hostTapped {
    HostViewController *vc = [[HostViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)guestTapped {
    GuestViewController *vc = [[GuestViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)settingsTapped {
    SettingsViewController *vc = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
