//
//  LauncherTerracottaViewController.h
//  Amethyst
//
//  Main "陶瓦联机" (Terracotta multiplayer) UI. Plugs into the Amethyst-iOS
//  side menu via LauncherMenuViewController (see patches/LauncherMenuViewController.patch).
//
//  The UI is a UITableViewController with three sections:
//    0. Mode picker: Create room (host) / Join room (guest)
//    1. Live status: room code, connection URL, player list
//    2. Actions: copy room code, copy URL, disconnect
//
//  All native calls go through TerracottaBridge. A 500ms timer polls
//  TerracottaBridge.pollState and refreshes the table, matching the polling
//  cadence HMCL uses (500ms — see HMCL TerracottaManager.java).
//

#import <UIKit/UIKit.h>
#import "TerracottaBridge.h"

NS_ASSUME_NONNULL_BEGIN

@interface LauncherTerracottaViewController : UITableViewController

/// Player name to advertise. If nil, "Terracotta Anonymous Host/Guest" is
/// used by the Rust side. The launcher should set this from the active
/// Microsoft account before presenting this controller.
@property (nonatomic, copy, nullable) NSString *playerName;

@end

NS_ASSUME_NONNULL_END
