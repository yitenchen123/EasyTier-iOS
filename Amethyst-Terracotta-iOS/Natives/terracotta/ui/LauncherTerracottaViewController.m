//
//  LauncherTerracottaViewController.m
//  Amethyst
//

#import "LauncherTerracottaViewController.h"
#import "TerracottaBridge.h"
#import "TerracottaLog.h"

typedef NS_ENUM(NSInteger, TTMode) {
    TTModeIdle    = 0,  // not yet started
    TTModeHost    = 1,  // hosting
    TTModeGuest   = 2,  // joining
};

typedef NS_ENUM(NSInteger, TTSection) {
    TTSectionMode     = 0,
    TTSectionStatus   = 1,
    TTSectionActions  = 2,
    TTSectionCount    = 3,
};

@interface LauncherTerracottaViewController ()
@property (nonatomic, strong) TerracottaBridge *bridge;
@property (nonatomic) TTMode mode;
@property (nonatomic, strong, nullable) TerracottaStateSnapshot *lastSnapshot;
@property (nonatomic, strong, nullable) NSTimer *pollTimer;
@property (nonatomic, strong) UITextField *roomInputField;
@property (nonatomic, strong) UITextField *playerInputField;
@property (nonatomic, strong) UIAlertController *loadingAlert;
@end

@implementation LauncherTerracottaViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Terracotta.Title", @"陶瓦联机");
    self.tableView.tableFooterView = [UIView new];
    self.tableView.allowsSelectionDuringEditing = NO;

    _bridge = TerracottaBridge.shared;
    _mode = TTModeIdle;

    [self ensureEngineStarted];

    // Player name field default (Amethyst stores the active account name in
    // a preference; the launcher should set -playerName before pushing this
    // VC. Fallback to a generic name.)
    if (self.playerName.length == 0) {
        self.playerName = @"Amethyst Player";
    }

    // Agreements notice (matches HMCL TERRACOTTA_AGREEMENT_VERSION gate).
    [self showAgreementOnce];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startPolling];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPolling];
}

#pragma mark - Engine bootstrap

- (void)ensureEngineStarted {
    if (self.bridge.isStarted) return;

    // POJAV_HOME is the standard Amethyst/Pojav working directory.
    NSString *pojavHome = NSProcessInfo.processInfo.environment[@"POJAV_HOME"];
    if (pojavHome.length == 0) {
        // Fallback to Documents directory.
        pojavHome = [NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@"terracotta"];
    }
    NSString *logPath = [pojavHome stringByAppendingPathComponent:@"terracotta.log"];

    NSError *err = nil;
    if (![self.bridge startWithWorkingDirectory:pojavHome
                                    loggingPath:logPath
                                          error:&err]) {
        [self showAlertWithTitle:@"启动联机组件失败"
                          message:err.localizedDescription ?: @"未知错误"];
    }
}

#pragma mark - Agreement

- (void)showAgreementOnce {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSInteger agreed = [ud integerForKey:@"terracotta.agreement.version"];
    if (agreed >= 2) return;  // TERRACOTTA_AGREEMENT_VERSION = 2

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"陶瓦联机协议"
                         message:@"陶瓦联机是第三方开源自由软件，由 Burning_TNT 开发。\n\n"
                                  @"它通过 EasyTier 建立虚拟网络，使你与好友的 Minecraft 世界可以互相联机。\n\n"
                                  @"继续使用即表示你已了解并同意该协议。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"同意并继续"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [ud setInteger:2 forKey:@"terracotta.agreement.version"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Polling

- (void)startPolling {
    [self stopPolling];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                      target:self
                                                    selector:@selector(onPoll)
                                                    userInfo:nil
                                                     repeats:YES];
    [self onPoll];  // immediate first tick
}

- (void)stopPolling {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

- (void)onPoll {
    TerracottaStateSnapshot *snap = self.bridge.pollState;
    if (!snap) return;

    // Detect state transitions for toast notifications.
    TerracottaState oldState = self.lastSnapshot.state;
    TerracottaState newState = snap.state;
    self.lastSnapshot = snap;

    // Auto-dismiss the loading alert when we leave the transitional states.
    if (self.loadingAlert) {
        BOOL transitional = (newState == TerracottaStateHostScanning ||
                             newState == TerracottaStateHostStarting ||
                             newState == TerracottaStateGuestConnecting ||
                             newState == TerracottaStateGuestStarting);
        if (!transitional) {
            [self.loadingAlert dismissViewControllerAnimated:YES completion:nil];
            self.loadingAlert = nil;
        }
    }

    // Auto-set mode based on state (so UI updates even if user backgrounds app).
    if (newState == TerracottaStateHostOk || newState == TerracottaStateHostScanning ||
        newState == TerracottaStateHostStarting) {
        self.mode = TTModeHost;
    } else if (newState == TerracottaStateGuestOk ||
               newState == TerracottaStateGuestConnecting ||
               newState == TerracottaStateGuestStarting) {
        self.mode = TTModeGuest;
    } else if (newState == TerracottaStateWaiting || newState == TerracottaStateException) {
        // keep current mode label until user picks a new action
    }

    // Show toast on critical transitions.
    if (oldState != newState) {
        [self handleStateTransitionFrom:oldState to:newState snap:snap];
    }

    [self.tableView reloadData];
}

- (void)handleStateTransitionFrom:(TerracottaState)old
                              to:(TerracottaState)newState
                            snap:(TerracottaStateSnapshot *)snap {
    if (newState == TerracottaStateException) {
        [self showAlertWithTitle:@"联机出错"
                          message:snap.localizedDescription];
        self.mode = TTModeIdle;
        return;
    }
    if (newState == TerracottaStateHostOk && old != TerracottaStateHostOk) {
        // Auto-copy room code to clipboard when room is created (matches HMCL).
        if (snap.roomCode) {
            UIPasteboard.generalPasteboard.string = snap.roomCode;
            [self showToast:@"房间已创建，邀请码已复制到剪贴板"];
        }
    }
    if (newState == TerracottaStateGuestOk && old != TerracottaStateGuestOk) {
        [self showToast:@"已加入房间！在 Minecraft 多人游戏界面直接连接即可"];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return TTSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case TTSectionMode:    return 2;  // Create / Join
        case TTSectionStatus:  return [self statusRowCount];
        case TTSectionActions: return [self actionRowCount];
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case TTSectionMode:    return @"模式";
        case TTSectionStatus:  return @"状态";
        case TTSectionActions: return @"操作";
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TTCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"TTCell"];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }

    switch (indexPath.section) {
        case TTSectionMode:    [self configureModeCell:cell row:indexPath.row]; break;
        case TTSectionStatus:  [self configureStatusCell:cell row:indexPath.row]; break;
        case TTSectionActions: [self configureActionCell:cell row:indexPath.row]; break;
    }
    return cell;
}

#pragma mark - Section: Mode

- (void)configureModeCell:(UITableViewCell *)cell row:(NSInteger)row {
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    if (row == 0) {
        cell.textLabel.text = @"创建房间（房主）";
        cell.detailTextLabel.text = @"在你的 Minecraft 中按 ESC → 对局域网开放，然后点击这里";
        cell.imageView.image = [UIImage systemImageNamed:@"house.fill"];
    } else {
        cell.textLabel.text = @"加入房间（房客）";
        cell.detailTextLabel.text = @"输入好友分享的邀请码加入房间";
        cell.imageView.image = [UIImage systemImageNamed:@"person.2.fill"];
    }
}

#pragma mark - Section: Status

- (NSInteger)statusRowCount {
    TerracottaStateSnapshot *s = self.lastSnapshot;
    if (!s) return 1;
    NSInteger count = 1;  // always show state description
    if (s.roomCode) count++;
    if (s.url) count++;
    count += s.profiles.count;
    if (s.state == TerracottaStateGuestStarting) count++;  // difficulty row
    return count;
}

- (void)configureStatusCell:(UITableViewCell *)cell row:(NSInteger)row {
    TerracottaStateSnapshot *s = self.lastSnapshot;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.imageView.image = nil;

    if (!s) {
        if (row == 0) {
            cell.textLabel.text = @"未启动";
            cell.detailTextLabel.text = nil;
        }
        return;
    }

    NSInteger r = 0;
    if (r++ == row) {
        cell.textLabel.text = s.localizedDescription;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"状态索引: %ld", (long)s.index];
        return;
    }
    if (s.roomCode && r++ == row) {
        cell.textLabel.text = @"邀请码";
        cell.detailTextLabel.text = s.roomCode;
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize];
        return;
    }
    if (s.url && r++ == row) {
        cell.textLabel.text = @"Minecraft 连接地址";
        cell.detailTextLabel.text = s.url;
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize];
        return;
    }
    if (s.state == TerracottaStateGuestStarting && r++ == row) {
        cell.textLabel.text = @"NAT 穿透难度";
        cell.detailTextLabel.text = [self difficultyLabel:s.difficulty];
        return;
    }
    // Player profiles
    NSInteger profileIdx = row - r;
    if (profileIdx >= 0 && profileIdx < (NSInteger)s.profiles.count) {
        TerracottaProfile *p = s.profiles[profileIdx];
        cell.textLabel.text = p.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", p.kind, p.vendor];
        if ([p.kind isEqualToString:@"HOST"]) {
            cell.imageView.image = [UIImage systemImageNamed:@"crown.fill"];
        } else if ([p.kind isEqualToString:@"LOCAL"]) {
            cell.imageView.image = [UIImage systemImageNamed:@"person.fill"];
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"person"];
        }
        return;
    }
    cell.textLabel.text = @"";
    cell.detailTextLabel.text = nil;
}

- (NSString *)difficultyLabel:(TerracottaDifficulty)d {
    switch (d) {
        case TerracottaDifficultyEasiest: return @"最易（开放网络）";
        case TerracottaDifficultySimple:  return @"较易";
        case TerracottaDifficultyMedium:  return @"中等";
        case TerracottaDifficultyTough:   return @"较难（对称 NAT）";
        default: return @"未知";
    }
}

#pragma mark - Section: Actions

- (NSInteger)actionRowCount {
    TerracottaStateSnapshot *s = self.lastSnapshot;
    if (!s || s.state == TerracottaStateWaiting) return 0;
    NSInteger count = 1;  // always: disconnect
    if (s.roomCode) count++;  // copy room code
    if (s.url) count++;       // copy URL
    return count;
}

- (void)configureActionCell:(UITableViewCell *)cell row:(NSInteger)row {
    TerracottaStateSnapshot *s = self.lastSnapshot;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.imageView.image = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    NSInteger r = 0;
    if (s.roomCode && r++ == row) {
        cell.textLabel.text = @"复制邀请码";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.imageView.image = [UIImage systemImageNamed:@"doc.on.doc"];
        return;
    }
    if (s.url && r++ == row) {
        cell.textLabel.text = @"复制连接地址";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.imageView.image = [UIImage systemImageNamed:@"doc.on.doc"];
        return;
    }
    if (r++ == row) {
        cell.textLabel.text = @"断开联机";
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.imageView.image = [UIImage systemImageNamed:@"xmark.octagon"];
        return;
    }
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == TTSectionMode) {
        if (indexPath.row == 0) {
            [self startHost];
        } else {
            [self promptJoinRoom];
        }
        return;
    }
    if (indexPath.section == TTSectionActions) {
        TerracottaStateSnapshot *s = self.lastSnapshot;
        NSInteger r = 0;
        if (s.roomCode && r++ == indexPath.row) {
            UIPasteboard.generalPasteboard.string = s.roomCode;
            [self showToast:@"邀请码已复制"];
            return;
        }
        if (s.url && r++ == indexPath.row) {
            UIPasteboard.generalPasteboard.string = s.url;
            [self showToast:@"连接地址已复制"];
            return;
        }
        if (r++ == indexPath.row) {
            [self disconnect];
            return;
        }
    }
}

#pragma mark - Actions

- (void)startHost {
    if (!self.bridge.isStarted) {
        [self showAlertWithTitle:@"未就绪" message:@"联机组件启动失败，请查看日志"];
        return;
    }
    self.mode = TTModeHost;
    [self.bridge setScanningWithRoom:nil player:self.playerName];
    [self showLoadingAlertWithTitle:@"正在等待 Minecraft 局域网世界"
                            message:@"请在 Minecraft 中按 ESC → 对局域地开放"];
}

- (void)promptJoinRoom {
    if (!self.bridge.isStarted) {
        [self showAlertWithTitle:@"未就绪" message:@"联机组件启动失败，请查看日志"];
        return;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"加入房间"
                         message:@"请输入好友分享的邀请码（以 U/ 开头）"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"U/XXXX-XXXX-XXXX-XXXX";
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.spellCheckingType = UITextSpellCheckingTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"加入"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong __typeof__(weakSelf) strong = weakSelf;
        NSString *code = alert.textFields.firstObject.text;
        code = [code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (code.length == 0) return;
        if (![strong.bridge verifyRoomCode:code]) {
            [strong showAlertWithTitle:@"邀请码无效"
                                message:@"请检查邀请码格式（以 U/ 开头，例如 U/ABCD-EFGH-IJKL-MNOP）"];
            return;
        }
        strong.mode = TTModeGuest;
        if ([strong.bridge setGuestingWithRoom:code player:strong.playerName]) {
            [strong showLoadingAlertWithTitle:@"正在加入房间"
                                      message:@"正在通过 EasyTier 连接房主…"];
        } else {
            [strong showAlertWithTitle:@"加入失败"
                                message:@"无法加入房间，请先断开当前会话再试"];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)disconnect {
    self.mode = TTModeIdle;
    [self.bridge setWaiting];
    [self.tableView reloadData];
}

#pragma mark - UI helpers

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showLoadingAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
    // Loading alerts are auto-dismissed in onPoll when state transitions out.
    self.loadingAlert = alert;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showToast:(NSString *)message {
    // Simple toast via a transient UIAlertController.
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:toast animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [toast dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

@end
