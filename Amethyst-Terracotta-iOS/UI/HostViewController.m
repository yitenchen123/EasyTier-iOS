//
//  HostViewController.m
//  TerracottaHelper
//
//  Host mode flow:
//    1. User opens Amethyst-iOS, launches MC, clicks "Open to LAN".
//    2. User returns to this app, enters optional player name, taps "Start".
//    3. Terracotta scans for MC's LAN broadcast (UDP multicast 224.0.2.60:4445),
//       finds the MC port, generates a room code, starts EasyTier as host
//       (virtual IP 10.144.144.1), and exposes the MC port via TcpWhitelist.
//    4. This controller polls state every 500ms and updates the UI:
//         host-scanning → host-starting → host-ok (show room code)
//    5. The user shares the room code. Guests connect via EasyTier.
//    6. MC in Amethyst-iOS is accessible at 127.0.0.1:MC_PORT via the
//       EasyTier whitelist (10.144.144.1:MC_PORT → 127.0.0.1:MC_PORT).
//

#import "HostViewController.h"
#import "TerracottaBridge.h"
#import "TerracottaLog.h"

@interface HostViewController () <UITextFieldDelegate>

// Setup UI
@property (nonatomic, strong) UITextField *playerNameField;
@property (nonatomic, strong) UIButton *startButton;

// Status UI
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *roomCodeLabel;
@property (nonatomic, strong) UIButton *copyButton;
@property (nonatomic, strong) UILabel *playersTitleLabel;
@property (nonatomic, strong) UIStackView *playersStack;

// Control
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;

@end

@implementation HostViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"我是房主";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self setupUI];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // If we're leaving and still hosting, stop polling.
    // The actual EasyTier teardown happens when the user taps "Stop".
    // If the user just navigates back without stopping, the session continues.
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 20;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor
                                                   constant:20],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor
                                                       constant:24],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor
                                                        constant:-24],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor
                                                      constant:-20],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor
                                                     constant:-48],
    ]];

    // --- Instructions ---
    UILabel *instructions = [self makeLabelWithText:
        @"使用步骤：\n\n"
         "1. 打开 Amethyst-iOS，启动 Minecraft Java 版\n"
         "2. 进入单人世界，按 Esc → 「对局域网开放」\n"
         "3. 回到本 App，点击下方「开始扫描」\n"
         "4. 扫描到世界后会生成邀请码，分享给好友\n\n"
         "⚠️ 联机期间请保持本 App 在后台运行\n（已自动开启后台保活）"
        font:[UIFont systemFontOfSize:15]
        color:UIColor.secondaryLabelColor];
    [self.contentStack addArrangedSubview:instructions];

    // --- Player name ---
    self.playerNameField = [[UITextField alloc] init];
    self.playerNameField.placeholder = @"玩家名称（可选，留空使用默认）";
    self.playerNameField.borderStyle = UITextBorderStyleRoundedRect;
    self.playerNameField.font = [UIFont systemFontOfSize:16];
    self.playerNameField.delegate = self;
    self.playerNameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.playerNameField];

    // --- Start button ---
    self.startButton = [self makeButtonWithTitle:@"开始扫描并创建房间"
                                          color:UIColor.systemBlueColor
                                         action:@selector(startTapped)];
    [self.contentStack addArrangedSubview:self.startButton];

    // --- Status section (hidden until started) ---
    self.statusLabel = [self makeLabelWithText:@""
                                         font:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium]
                                        color:UIColor.labelColor];
    self.statusLabel.hidden = YES;
    [self.contentStack addArrangedSubview:self.statusLabel];

    // Room code display
    UIView *roomCard = [[UIView alloc] init];
    roomCard.backgroundColor = UIColor.secondarySystemBackgroundColor;
    roomCard.layer.cornerRadius = 12;
    roomCard.translatesAutoresizingMaskIntoConstraints = NO;

    self.roomCodeLabel = [[UILabel alloc] init];
    self.roomCodeLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold
                                                      monospacedDigit:NO];
    self.roomCodeLabel.textAlignment = NSTextAlignmentCenter;
    self.roomCodeLabel.text = @"";
    self.roomCodeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [roomCard addSubview:self.roomCodeLabel];

    self.copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.copyButton setTitle:@"复制邀请码" forState:UIControlStateNormal];
    self.copyButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [self.copyButton addTarget:self action:@selector(copyTapped)
              forControlEvents:UIControlEventTouchUpInside];
    self.copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [roomCard addSubview:self.copyButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.roomCodeLabel.topAnchor constraintEqualToAnchor:roomCard.topAnchor constant:16],
        [self.roomCodeLabel.leadingAnchor constraintEqualToAnchor:roomCard.leadingAnchor constant:16],
        [self.roomCodeLabel.trailingAnchor constraintEqualToAnchor:roomCard.trailingAnchor constant:-16],
        [self.copyButton.topAnchor constraintEqualToAnchor:self.roomCodeLabel.bottomAnchor constant:8],
        [self.copyButton.centerXAnchor constraintEqualToAnchor:roomCard.centerXAnchor],
        [self.copyButton.bottomAnchor constraintEqualToAnchor:roomCard.bottomAnchor constant:-12],
    ]];

    roomCard.hidden = YES;
    [self.contentStack addArrangedSubview:roomCard];

    // Players list
    self.playersTitleLabel = [self makeLabelWithText:@"已加入的玩家"
                                               font:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]
                                              color:UIColor.secondaryLabelColor];
    self.playersTitleLabel.hidden = YES;
    [self.contentStack addArrangedSubview:self.playersTitleLabel];

    self.playersStack = [[UIStackView alloc] init];
    self.playersStack.axis = UILayoutConstraintAxisVertical;
    self.playersStack.spacing = 8;
    self.playersStack.alignment = UIStackViewAlignmentFill;
    self.playersStack.hidden = YES;
    [self.contentStack addArrangedSubview:self.playersStack];

    // Stop button
    self.stopButton = [self makeButtonWithTitle:@"停止联机并返回"
                                         color:UIColor.systemRedColor
                                        action:@selector(stopTapped)];
    self.stopButton.hidden = YES;
    [self.contentStack addArrangedSubview:self.stopButton];
}

#pragma mark - Actions

- (void)startTapped {
    [self.playerNameField resignFirstResponder];

    // Transition to Waiting first to ensure a clean state, then start scanning.
    [[TerracottaBridge shared] setWaiting];

    NSString *player = self.playerNameField.text;
    if (player.length == 0) player = nil;

    TerracottaLogInfo(@"Starting host scan. player=%@", player ?: @"(default)");
    [[TerracottaBridge shared] setScanningWithRoom:nil player:player];

    // Disable setup UI, show status UI
    self.playerNameField.enabled = NO;
    self.startButton.enabled = NO;
    self.startButton.alpha = 0.5;
    self.statusLabel.hidden = NO;
    self.stopButton.hidden = NO;

    // Start polling
    [self startPolling];
}

- (void)stopTapped {
    [self stopPolling];
    [[TerracottaBridge shared] setWaiting];

    // Reset UI
    self.playerNameField.enabled = YES;
    self.startButton.enabled = YES;
    self.startButton.alpha = 1.0;
    self.statusLabel.text = @"";
    self.statusLabel.hidden = YES;
    self.roomCodeLabel.text = @"";
    self.roomCodeLabel.superview.hidden = YES;
    self.playersTitleLabel.hidden = YES;
    self.playersStack.hidden = YES;
    [self.playersStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.stopButton.hidden = YES;

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)copyTapped {
    if (self.roomCodeLabel.text.length > 0) {
        [UIPasteboard generalPasteboard].string = self.roomCodeLabel.text;
        // Brief visual feedback
        NSString *orig = [self.copyButton titleForState:UIControlStateNormal];
        [self.copyButton setTitle:@"已复制 ✓" forState:UIControlStateNormal];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.copyButton setTitle:orig forState:UIControlStateNormal];
        });
    }
}

#pragma mark - State polling

- (void)startPolling {
    [self stopPolling];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                      target:self
                                                    selector:@selector(pollState)
                                                    userInfo:nil
                                                     repeats:YES];
    [self pollState]; // immediate first poll
}

- (void)stopPolling {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

- (void)pollState {
    TerracottaStateSnapshot *snap = [[TerracottaBridge shared] pollState];
    if (!snap) return;

    self.statusLabel.text = [snap localizedDescription];

    switch (snap.state) {
        case TerracottaStateHostStarting:
            // Room code is available during host-starting
            if (snap.roomCode.length > 0) {
                self.roomCodeLabel.text = snap.roomCode;
                self.roomCodeLabel.superview.hidden = NO;
            }
            break;

        case TerracottaStateHostOk:
            // Room is ready — show room code and player list
            if (snap.roomCode.length > 0) {
                self.roomCodeLabel.text = snap.roomCode;
                self.roomCodeLabel.superview.hidden = NO;
            }
            [self updatePlayersList:snap.profiles];
            break;

        case TerracottaStateException:
            [self stopPolling];
            // Show error alert
            [self showAlertWithTitle:@"联机出错"
                              message:[snap localizedDescription]];
            // Re-enable setup
            self.playerNameField.enabled = YES;
            self.startButton.enabled = YES;
            self.startButton.alpha = 1.0;
            self.stopButton.hidden = YES;
            break;

        case TerracottaStateHostScanning:
            // Still scanning for MC
            break;

        default:
            break;
    }
}

- (void)updatePlayersList:(NSArray<TerracottaProfile *> *)profiles {
    if (profiles.count == 0) {
        self.playersTitleLabel.hidden = YES;
        self.playersStack.hidden = YES;
        return;
    }

    self.playersTitleLabel.hidden = NO;
    self.playersStack.hidden = NO;

    // Clear and rebuild
    [self.playersStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    for (TerracottaProfile *p in profiles) {
        NSString *role = @"";
        if ([p.kind isEqualToString:@"HOST"]) role = @"🏠 房主";
        else if ([p.kind isEqualToString:@"GUEST"]) role = @"🎮 玩家";
        else if ([p.kind isEqualToString:@"LOCAL"]) role = @"📱 本机";

        UILabel *label = [[UILabel alloc] init];
        label.text = [NSString stringWithFormat:@"%@  %@", role, p.name];
        label.font = [UIFont systemFontOfSize:15];
        label.textColor = UIColor.labelColor;
        label.backgroundColor = UIColor.secondarySystemBackgroundColor;
        label.layer.cornerRadius = 8;
        label.clipsToBounds = YES;
        label.textAlignment = NSTextAlignmentCenter;
        [label.heightAnchor constraintGreaterThanOrEqualToConstant:36].active = YES;
        [self.playersStack addArrangedSubview:label];
    }
}

#pragma mark - Helpers

- (UILabel *)makeLabelWithText:(NSString *)text
                         font:(UIFont *)font
                        color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UIButton *)makeButtonWithTitle:(NSString *)title
                            color:(UIColor *)color
                           action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.backgroundColor = color;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    btn.layer.cornerRadius = 14;
    btn.contentEdgeInsets = UIEdgeInsetsMake(16, 16, 16, 16);
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    return btn;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
