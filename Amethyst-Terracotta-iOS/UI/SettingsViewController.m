//
//  SettingsViewController.m
//  TerracottaHelper
//
//  Shows Terracotta/EasyTier version, public node list, log path,
//  and interoperability info.
//

#import "SettingsViewController.h"
#import "TerracottaBridge.h"
#import "TerracottaLog.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *nodesLabel;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
    [self loadMetadata];
    [self loadPublicNodes];
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 16;
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

    // --- Version info ---
    [self addSectionTitle:@"版本信息"];
    [self addInfoCardWithLines:@[
        @[@"Terracotta 版本", @"加载中…"],
        @[@"EasyTier 版本", @"加载中…"],
        @[@"编译时间", @"加载中…"],
    ]];

    // --- Interop info ---
    [self addSectionTitle:@"兼容性"];
    UILabel *interop = [self makeLabelWithText:
        @"本 App 使用与 HMCL / FCL / ZalithLauncher2 完全相同的\n"
         "burningtnt/Terracotta 协议实现（同一份 Rust 源码），\n"
         "房间码格式、EasyTier 配置、Scaffolding 协议均完全一致，\n"
         "可 100% 互相联机。\n\n"
         "支持配合以下启动器使用：\n"
         "• Amethyst-iOS（官方版）\n"
         "• Amethyst-iOS-MyRemastered（改版）\n"
         "• 无需修改 Amethyst-iOS 本体"
        font:[UIFont systemFontOfSize:14]
        color:UIColor.secondaryLabelColor];
    [self.contentStack addArrangedSubview:interop];

    // --- Public nodes ---
    [self addSectionTitle:@"公共节点"];
    self.nodesLabel = [self makeLabelWithText:@"正在获取…"
                                        font:[UIFont systemFontOfSize:14]
                                       color:UIColor.secondaryLabelColor];
    [self.contentStack addArrangedSubview:self.nodesLabel];

    // --- Log path ---
    [self addSectionTitle:@"日志"];
    NSString *docs = [NSSearchPathForDirectoriesInDomains(
                         NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *logPath = [NSString stringWithFormat:@"%@/terracotta/terracotta.log", docs];
    UILabel *logLabel = [self makeLabelWithText:[NSString stringWithFormat:@"日志文件路径：\n%@", logPath]
                                         font:[UIFont fontWithName:@"Menlo" size:12]
                                        color:UIColor.tertiaryLabelColor];
    [self.contentStack addArrangedSubview:logLabel];

    // --- About ---
    [self addSectionTitle:@"关于"];
    UILabel *about = [self makeLabelWithText:
        @"陶瓦联机助手 for iOS\n"
         "独立 App，配合 Amethyst-iOS 使用\n"
         "基于 burningtnt/Terracotta + EasyTier"
        font:[UIFont systemFontOfSize:14]
        color:UIColor.secondaryLabelColor];
    [self.contentStack addArrangedSubview:about];
}

- (void)loadMetadata {
    NSString *meta = [[TerracottaBridge shared] metadata];
    if (!meta) return;

    // Metadata format: "version\ntimestamp\neasytier_version"
    NSArray *parts = [meta componentsSeparatedByString:@"\n"];
    if (parts.count >= 3) {
        // Update the version info card (second arranged subview after section title)
        // The version card is at index 1 (after the section title at index 0)
        UIView *card = self.contentStack.arrangedSubviews[1];
        if ([card isKindOfClass:[UIStackView class]]) {
            UIStackView *cardStack = (UIStackView *)card;
            // Update the three rows
            NSArray *values = @[parts[0], parts[2], parts[1]];
            for (int i = 0; i < cardStack.arrangedSubviews.count && i < values.count; i++) {
                UIStackView *row = (UIStackView *)cardStack.arrangedSubviews[i];
                UILabel *valueLabel = (UILabel *)row.arrangedSubviews[1];
                // Format timestamp
                if (i == 2) {
                    NSTimeInterval ts = [values[i] doubleValue] / 1000.0;
                    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
                    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
                    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
                    valueLabel.text = [fmt stringFromDate:date];
                } else {
                    valueLabel.text = values[i];
                }
            }
        }
    }
}

- (void)loadPublicNodes {
    [[TerracottaBridge shared] fetchPublicNodesWithCompletion:^(NSArray<NSString *> *nodes, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || nodes.count == 0) {
                self.nodesLabel.text = @"获取失败（将使用内置默认节点）";
            } else {
                NSMutableString *text = [NSMutableString string];
                for (NSString *node in nodes) {
                    [text appendFormat:@"• %@\n", node];
                }
                self.nodesLabel.text = text;
            }
        });
    }];
}

#pragma mark - UI helpers

- (void)addSectionTitle:(NSString *)title {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    label.textColor = UIColor.labelColor;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:label];
}

- (void)addInfoCardWithLines:(NSArray<NSArray<NSString *> *> *)lines {
    UIStackView *card = [[UIStackView alloc] init];
    card.axis = UILayoutConstraintAxisVertical;
    card.spacing = 8;
    card.alignment = UIStackViewAlignmentFill;
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layoutMargins = UIEdgeInsetsMake(12, 16, 12, 16);
    card.insetsLayoutMarginsFromSafeArea = NO;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 12;
    card.clipsToBounds = YES;

    for (NSArray<NSString *> *line in lines) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.distribution = UIStackViewDistributionFill;
        row.alignment = UIStackViewAlignmentFirstBaseline;
        row.spacing = 8;

        UILabel *key = [[UILabel alloc] init];
        key.text = line[0];
        key.font = [UIFont systemFontOfSize:14];
        key.textColor = UIColor.secondaryLabelColor;

        UILabel *value = [[UILabel alloc] init];
        value.text = line.count > 1 ? line[1] : @"";
        value.font = [UIFont systemFontOfSize:14];
        value.textColor = UIColor.labelColor;
        value.textAlignment = NSTextAlignmentRight;
        value.adjustsFontSizeToFitWidth = YES;
        value.minimumScaleFactor = 0.7;

        [row addArrangedSubview:key];
        [row addArrangedSubview:value];
        [card addArrangedSubview:row];
    }

    [self.contentStack addArrangedSubview:card];
}

- (UILabel *)makeLabelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

@end
