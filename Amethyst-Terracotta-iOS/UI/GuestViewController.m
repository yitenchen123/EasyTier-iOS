//
//  GuestViewController.m
//  TerracottaHelper
//
//  Guest mode flow:
//    1. User enters the room code (U/XXXX-XXXX-XXXX-XXXX) from the host.
//    2. User enters optional player name, taps "Join".
//    3. Terracotta parses the code, starts EasyTier as guest (DHCP virtual IP),
//       discovers the host (10.144.144.1) via the Scaffolding protocol,
//       and sets up port_forward: 0.0.0.0:LOCAL → 10.144.144.1:MC_PORT.
//    4. This controller polls state every 500ms:
//         guest-connecting → guest-starting → guest-ok (show connect URL)
//    5. When guest-ok: user opens Amethyst-iOS, adds a server at the
//       displayed address (127.0.0.1 or 127.0.0.1:PORT), and joins.
//    6. EasyTier routes the traffic through the virtual network to the host.
//

#import "GuestViewController.h"
#import "TerracottaBridge.h"
#import "TerracottaLog.h"

@interface GuestViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *roomCodeField;
@property (nonatomic, strong) UITextField *playerNameField;
@property (nonatomic, strong) UIButton *joinButton;

@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *serverCard;
@property (nonatomic, strong) UILabel *serverAddressLabel;
@property (nonatomic, strong) UIButton *copyServerButton;
@property (nonatomic, strong) UILabel *playersTitleLabel;
@property (nonatomic, strong) UIStackView *playersStack;

@property (nonatomic, strong) UIButton *disconnectButton;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;

@end

@implementation GuestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"我是房客";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self setupUI];
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
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:20],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:24],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-24],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-48],
    ]];

    // --- Instructions ---
    UILabel *instructions = [self makeLabelWithText:
        @"使用步骤：\n\n"
         "1. 输入房主给你的邀请码\n"
         "2. 点击「加入房间」\n"
         "3. 连接成功后，打开 Amethyst-iOS\n"
         "4. 在 MC 中添加服务器，地址见下方\n\n"
         "⚠️ 联机期间请保持本 App 在后台运行\n（已自动开启后台保活）"
        font:[UIFont systemFontOfSize:15]
        color:UIColor.secondaryLabelColor];
    [self.contentStack addArrangedSubview:instructions];

    // --- Room code input ---
    UILabel *roomLabel = [self makeLabelWithText:@"邀请码"
                                           font:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]
                                          color:UIColor.secondaryLabelColor];
    [self.contentStack addArrangedSubview:roomLabel];

    self.roomCodeField = [[UITextField alloc] init];
    self.roomCodeField.placeholder = @"U/XXXX-XXXX-XXXX-XXXX";
    self.roomCodeField.borderStyle = UITextBorderStyleRoundedRect;
    self.roomCodeField.font = [UIFont systemFontOfSize:18 monospacedDigitFontOfSizeWeight:UIFontWeightRegular];
    self.roomCodeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.roomCodeField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.roomCodeField.delegate = self;
    self.roomCodeField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.roomCodeField];

    // --- Player name ---
    UILabel *playerLabel = [self makeLabelWithText:@"玩家名称（可选）"
                                             font:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]
                                            color:UIColor.secondaryLabelColor];
    [self.contentStack addArrangedSubview:playerLabel];

    self.playerNameField = [[UITextField alloc] init];
    self.playerNameField.placeholder = @"留空使用默认名称";
    self.playerNameField.borderStyle = UITextBorderStyleRoundedRect;
    self.playerNameField.font = [UIFont systemFontOfSize:16];
    self.playerNameField.delegate = self;
    self.playerNameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.playerNameField];

    // --- Join button ---
    self.joinButton = [self makeButtonWithTitle:@"加入房间"
                                          color:UIColor.systemGreenColor
                                         action:@selector(joinTapped)];
    [self.contentStack addArrangedSubview:self.joinButton];

    // --- Status ---
    self.statusLabel = [self makeLabelWithText:@""
                                         font:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium]
                                        color:UIColor.labelColor];
    self.statusLabel.hidden = YES;
    [self.contentStack addArrangedSubview:self.statusLabel];

    // --- Server address card ---
    self.serverCard = [[UIView alloc] init];
    self.serverCard.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.serverCard.layer.cornerRadius = 12;
    self.serverCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.serverCard.hidden = YES;

    UILabel *serverTitle = [[UILabel alloc] init];
    serverTitle.text = @"在 MC 中添加服务器，地址为：";
    serverTitle.font = [UIFont systemFontOfSize:14];
    serverTitle.textColor = UIColor.secondaryLabelColor;
    serverTitle.textAlignment = NSTextAlignmentCenter;
    serverTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.serverCard addSubview:serverTitle];

    self.serverAddressLabel = [[UILabel alloc] init];
    self.serverAddressLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    self.serverAddressLabel.textAlignment = NSTextAlignmentCenter;
    self.serverAddressLabel.text = @"127.0.0.1";
    self.serverAddressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.serverCard addSubview:self.serverAddressLabel];

    self.copyServerButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.copyServerButton setTitle:@"复制地址" forState:UIControlStateNormal];
    self.copyServerButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [self.copyServerButton addTarget:self action:@selector(copyServerTapped)
                    forControlEvents:UIControlEventTouchUpInside];
    self.copyServerButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.serverCard addSubview:self.copyServerButton];

    [NSLayoutConstraint activateConstraints:@[
        [serverTitle.topAnchor constraintEqualToAnchor:self.serverCard.topAnchor constant:16],
        [serverTitle.leadingAnchor constraintEqualToAnchor:self.serverCard.leadingAnchor constant:16],
        [serverTitle.trailingAnchor constraintEqualToAnchor:self.serverCard.trailingAnchor constant:-16],
        [self.serverAddressLabel.topAnchor constraintEqualToAnchor:serverTitle.bottomAnchor constant:8],
        [self.serverAddressLabel.leadingAnchor constraintEqualToAnchor:self.serverCard.leadingAnchor constant:16],
        [self.serverAddressLabel.trailingAnchor constraintEqualToAnchor:self.serverCard.trailingAnchor constant:-16],
        [self.copyServerButton.topAnchor constraintEqualToAnchor:self.serverAddressLabel.bottomAnchor constant:8],
        [self.copyServerButton.centerXAnchor constraintEqualToAnchor:self.serverCard.centerXAnchor],
        [self.copyServerButton.bottomAnchor constraintEqualToAnchor:self.serverCard.bottomAnchor constant:-12],
    ]];

    [self.contentStack addArrangedSubview:self.serverCard];

    // --- Players ---
    self.playersTitleLabel = [self makeLabelWithText:@"房间内玩家"
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

    // --- Disconnect ---
    self.disconnectButton = [self makeButtonWithTitle:@"断开连接并返回"
                                               color:UIColor.systemRedColor
                                              action:@selector(disconnectTapped)];
    self.disconnectButton.hidden = YES;
    [self.contentStack addArrangedSubview:self.disconnectButton];
}

#pragma mark - Actions

- (void)joinTapped {
    [self.roomCodeField resignFirstResponder];
    [self.playerNameField resignFirstResponder];

    NSString *room = self.roomCodeField.text;
    if (room.length == 0) {
        [self showAlertWithTitle:@"请输入邀请码" message:nil];
        return;
    }

    // Validate room code
    if (![[TerracottaBridge shared] verifyRoomCode:room]) {
        [self showAlertWithTitle:@"邀请码无效"
                          message:@"请检查邀请码格式是否为 U/XXXX-XXXX-XXXX-XXXX"];
        return;
    }

    NSString *player = self.playerNameField.text;
    if (player.length == 0) player = nil;

    // Reset to waiting first, then join
    [[TerracottaBridge shared] setWaiting];

    BOOL ok = [[TerracottaBridge shared] setGuestingWithRoom:room player:player];
    if (!ok) {
        [self showAlertWithTitle:@"加入失败"
                          message:@"无法加入房间，请重试。可能的原因：邀请码无效或当前已有联机会话。"];
        return;
    }

    TerracottaLogInfo(@"Joining room: %@ player=%@", room, player ?: @"(default)");

    // Disable setup UI
    self.roomCodeField.enabled = NO;
    self.playerNameField.enabled = NO;
    self.joinButton.enabled = NO;
    self.joinButton.alpha = 0.5;
    self.statusLabel.hidden = NO;
    self.disconnectButton.hidden = NO;

    [self startPolling];
}

- (void)disconnectTapped {
    [self stopPolling];
    [[TerracottaBridge shared] setWaiting];

    self.roomCodeField.enabled = YES;
    self.playerNameField.enabled = YES;
    self.joinButton.enabled = YES;
    self.joinButton.alpha = 1.0;
    self.statusLabel.text = @"";
    self.statusLabel.hidden = YES;
    self.serverCard.hidden = YES;
    self.playersTitleLabel.hidden = YES;
    self.playersStack.hidden = YES;
    [self.playersStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.disconnectButton.hidden = YES;

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)copyServerTapped {
    if (self.serverAddressLabel.text.length > 0) {
        [UIPasteboard generalPasteboard].string = self.serverAddressLabel.text;
        NSString *orig = [self.copyServerButton titleForState:UIControlStateNormal];
        [self.copyServerButton setTitle:@"已复制 ✓" forState:UIControlStateNormal];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.copyServerButton setTitle:orig forState:UIControlStateNormal];
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
    [self pollState];
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
        case TerracottaStateGuestConnecting:
            // Still connecting to the EasyTier network
            break;

        case TerracottaStateGuestStarting:
            // Found the host, connecting to scaffolding server
            if (snap.roomCode.length > 0) {
                // Optionally show the room code
            }
            break;

        case TerracottaStateGuestOk:
            // Connected! Show the server address.
            if (snap.url.length > 0) {
                self.serverAddressLabel.text = snap.url;
                self.serverCard.hidden = NO;
            }
            [self updatePlayersList:snap.profiles];
            break;

        case TerracottaStateException:
            [self stopPolling];
            [self showAlertWithTitle:@"联机出错" message:[snap localizedDescription]];
            self.roomCodeField.enabled = YES;
            self.playerNameField.enabled = YES;
            self.joinButton.enabled = YES;
            self.joinButton.alpha = 1.0;
            self.disconnectButton.hidden = YES;
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

- (UILabel *)makeLabelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UIButton *)makeButtonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
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
