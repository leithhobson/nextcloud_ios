//
//  CCFavorites.m
//  Nextcloud
//
//  Created by Marino Faggiana on 16/01/17.
//  Copyright (c) 2017 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "CCFavorites.h"
#import "AppDelegate.h"

#import "NCBridgeSwift.h"

@interface CCFavorites ()
{
    AppDelegate *appDelegate;
    
    // Automatic Upload Folder
    NSString *autoUploadFileName;
    NSString *autoUploadDirectory;
    
    UIDocumentInteractionController *docController;
    
    // Datasource
    CCSectionDataSourceMetadata *sectionDataSource;
    
    BOOL livePhoto;
}
@end

@implementation CCFavorites

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Init =====
#pragma --------------------------------------------------------------------------------------------

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder])  {
        appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
        appDelegate.activeFavorites = self;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"CCCellMain" bundle:nil] forCellReuseIdentifier:@"CellMain"];
    [self.tableView registerNib:[UINib nibWithNibName:@"CCCellMainTransfer" bundle:nil] forCellReuseIdentifier:@"CellMainTransfer"];
    
    // Notification
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(triggerProgressTask:) name:k_notificationCenter_progressTask object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changeTheming) name:k_notificationCenter_changeTheming object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDatasource) name:k_notificationCenter_reloadDataSource object:nil];

    // Metadata
    self.metadata = [tableMetadata new];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 1)];
    self.tableView.emptyDataSetDelegate = self;
    self.tableView.emptyDataSetSource = self;
    self.tableView.delegate = self;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 35, 0);

    // Register for 3D Touch Previewing if available
    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)] && (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable))
    {
        [self registerForPreviewingWithDelegate:self sourceView:self.view];
    }
    
    // calculate _serverUrl
    if (!_serverUrl) {
        _serverUrl = nil;
    }
    
    // Title
    if (_titleViewControl)
        self.title = _titleViewControl;
    else
        self.title = NSLocalizedString(@"_favorites_", nil);
    
    [self changeTheming];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadDatasource];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Active Main
    appDelegate.activeFavorites = self;

    // test
    if (appDelegate.account.length == 0) {
        return;
    }
    
    if (self.serverUrl == nil) {
        [[NCNetworking shared] listingFavoritescompletionWithSelector:(selectorListingFavorite) completion:^(NSString *account, NSArray *metadatas, NSInteger errorCode, NSString *errorDescription) {
            for (tableMetadata *metadata in metadatas) {
                if (!metadata.directory && CCUtility.getFavoriteOffline) {
                    tableLocalFile *localFile = [[NCManageDatabase sharedInstance] getTableLocalFileWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", metadata.ocId]];
                    if (localFile == nil || ![localFile.etag isEqualToString:metadata.etag]) {
                        [[NCOperationQueue shared] downloadWithMetadata:metadata selector:selectorDownloadFile setFavorite:false];
                    }
                }
            }
            [self reloadDatasource];
        }];
    } else {
        [[NCNetworking shared] readFolderWithServerUrl:self.serverUrl account:appDelegate.account completion:^(NSString *account, tableMetadata *metadataFolder, NSArray *metadatas, NSArray *metadatasUpdate, NSArray *metadatasLocalUpdate, NSInteger errorCode, NSString *errorDescription) {
            if (errorCode == 0) {
                for (tableMetadata *metadata in metadatas) {
                    if (!metadata.directory && CCUtility.getFavoriteOffline) {
                        tableLocalFile *localFile = [[NCManageDatabase sharedInstance] getTableLocalFileWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", metadata.ocId]];
                        if (localFile == nil || ![localFile.etag isEqualToString:metadata.etag]) {
                            [[NCOperationQueue shared] downloadWithMetadata:metadata selector:selectorDownloadFile setFavorite:false];
                        }
                    }
                }
                [self reloadDatasource];
            }
        }];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== NotificationCenter ====
#pragma --------------------------------------------------------------------------------------------

- (void)triggerProgressTask:(NSNotification *)notification
{
    if (sectionDataSource.ocIdIndexPath != nil) {
        [[NCMainCommon sharedInstance] triggerProgressTask:notification sectionDataSourceocIdIndexPath:sectionDataSource.ocIdIndexPath tableView:self.tableView viewController:self serverUrlViewController:self.serverUrl];
    }
}

- (void)changeTheming
{
    [appDelegate changeTheming:self tableView:self.tableView collectionView:nil form:false];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== DZNEmptyDataSetSource ====
#pragma --------------------------------------------------------------------------------------------

- (CGFloat)verticalOffsetForEmptyDataSet:(UIScrollView *)scrollView
{
    //CGFloat height = self.tabBarController.tabBar.frame.size.height;
    return 0;
}

- (UIColor *)backgroundColorForEmptyDataSet:(UIScrollView *)scrollView
{
    return NCBrandColor.sharedInstance.backgroundView;
}

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"favorite"] width:300 height:300 color:NCBrandColor.sharedInstance.yellowFavorite];
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = [NSString stringWithFormat:@"%@", NSLocalizedString(@"_favorite_no_files_", nil)];
    
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:20.0f], NSForegroundColorAttributeName:[UIColor lightGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = [NSString stringWithFormat:@"\n%@", NSLocalizedString(@"_tutorial_favorite_view_", nil)];
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0], NSForegroundColorAttributeName: [UIColor lightGrayColor], NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (void)tapActionComment:(UITapGestureRecognizer *)tapGesture
{
    CGPoint location = [tapGesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    if (metadata) {
        [[NCMainCommon sharedInstance] openShareWithViewController:self metadata:metadata indexPage:1];
    }
}

- (void)tapActionShared:(UITapGestureRecognizer *)tapGesture
{
    CGPoint location = [tapGesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    if (metadata) {
        [[NCMainCommon sharedInstance] openShareWithViewController:self metadata:metadata indexPage:2];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Progress & Task Button =====
#pragma --------------------------------------------------------------------------------------------

- (void)cancelTaskButton:(id)sender withEvent:(UIEvent *)event
{
    UITouch *touch = [[event allTouches] anyObject];
    CGPoint location = [touch locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    if ([[NCMainCommon sharedInstance] isValidIndexPath:indexPath view:self.tableView]) {
        
        tableMetadata *metadataSection = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
        
        if (metadataSection) {
            
            tableMetadata *metadata = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", metadataSection.ocId]];
            if (metadata)
                [[NCMainCommon sharedInstance] cancelTransferMetadata:metadata reloadDatasource:true uploadStatusForcedStart:false];
        }
    }
}

- (void)cancelAllTask:(id)sender
{
    CGPoint location = [sender locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_cancel_all_task_", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [NCUtility.shared startActivityIndicatorWithView:self.view bottom:0];
        [[NCMainCommon sharedInstance] cancelAllTransfer];
        [NCUtility.shared stopActivityIndicator];
    }]];
    
    [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_cancel_", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { }]];
    
    alertController.popoverPresentationController.sourceView = self.tableView;
    alertController.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        [alertController.view layoutIfNeeded];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Peek & Pop  =====
#pragma --------------------------------------------------------------------------------------------

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location
{
    CGPoint convertedLocation = [self.view convertPoint:location toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:convertedLocation];
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    CCCellMain *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    
    if (cell) {
        previewingContext.sourceRect = cell.frame;
        CCPeekPop *viewController = [[UIStoryboard storyboardWithName:@"CCPeekPop" bundle:nil] instantiateViewControllerWithIdentifier:@"PeekPopImagePreview"];
        
        viewController.metadata = metadata;
        viewController.imageFile = cell.file.image;
        viewController.showOpenIn = true;
        viewController.showShare = false;
        viewController.showOpenQuickLook = [[NCUtility shared] isQuickLookDisplayableWithMetadata:metadata];
       
        return viewController;
    }
    
    return nil;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit
{
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:previewingContext.sourceRect.origin];
    
    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== menu action : Favorite, More, Delete [swipe] =====
#pragma --------------------------------------------------------------------------------------------

- (BOOL)canOpenMenuAction:(tableMetadata *)metadata
{
    return YES;
}

- (BOOL)swipeTableCell:(MGSwipeTableCell *)cell canSwipe:(MGSwipeDirection)direction
{
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    return [self canOpenMenuAction:metadata];
}

- (BOOL)swipeTableCell:(MGSwipeTableCell *)cell tappedButtonAtIndex:(NSInteger)index direction:(MGSwipeDirection)direction fromExpansion:(BOOL)fromExpansion
{
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    
    if (direction == MGSwipeDirectionRightToLeft) {
        
        [self actionDelete:indexPath];
    }
    
    if (direction == MGSwipeDirectionLeftToRight) {
        
        tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
        [[NCNetworking shared] favoriteMetadata:metadata urlBase:appDelegate.urlBase completion:^(NSInteger errorCode, NSString *errorDescription) { }];
    }
    
    return YES;
}

- (void)actionDelete:(NSIndexPath *)indexPath
{
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_delete_", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[NCNetworking shared] deleteMetadata:metadata account:appDelegate.account urlBase:appDelegate.urlBase completion:^(NSInteger errorCode, NSString *errorDescription) { }];
    }]];
    
   
    [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_cancel_", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    }]];
    
    alertController.popoverPresentationController.sourceView = self.tableView;
    alertController.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        [alertController.view layoutIfNeeded];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)actionMore:(UITapGestureRecognizer *)gestureRecognizer
{
    CGPoint touch = [gestureRecognizer locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touch];    
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    [self toggleMoreMenuWithViewController:self.tabBarController indexPath:indexPath metadata:metadata];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Table ====
#pragma --------------------------------------------------------------------------------------------

- (tableMetadata *)setSelfMetadataFromIndexPath:(NSIndexPath *)indexPath
{
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    return metadata;
}

- (void)reloadDatasource
{
    // test
    if (appDelegate.account.length == 0) { // || self.view.window == nil) {
        return;
    }
    
    NSArray *recordsTableMetadata;
    NSString *sorted = [CCUtility getOrderSettings];
    if ([sorted isEqualToString:@"fileName"]) sorted = @"fileName";
    
    // live photo
    livePhoto =  [CCUtility getLivePhoto];
    
    // get auto upload folder
    autoUploadFileName = [[NCManageDatabase sharedInstance] getAccountAutoUploadFileName];
    autoUploadDirectory = [[NCManageDatabase sharedInstance] getAccountAutoUploadDirectoryWithUrlBase:appDelegate.urlBase account:appDelegate.account];
    
    if (!_serverUrl) {
        
        recordsTableMetadata = [[NCManageDatabase sharedInstance] getMetadatasWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND favorite == true", appDelegate.account] page:0 limit:0 sorted:@"fileName" ascending:NO];
        
    } else {
        
        recordsTableMetadata = [[NCManageDatabase sharedInstance] getMetadatasWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.account, self.serverUrl] page:0 limit:0 sorted:@"fileName" ascending:NO];
    }
    
    sectionDataSource = [CCSectionMetadata creataDataSourseSectionMetadata:recordsTableMetadata listProgressMetadata:nil groupByField:nil filterTypeFileImage:NO filterTypeFileVideo:NO filterLivePhoto:YES sorted:sorted ascending:[CCUtility getAscendingSettings] account:appDelegate.account];
    
    [self.tableView reloadData];
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [[sectionDataSource.sectionArrayRow allKeys] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[sectionDataSource.sectionArrayRow objectForKey:[sectionDataSource.sections objectAtIndex:section]] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    tableShare *shareCell;
    tableMetadata *metadataFolder;
   
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    if (metadata == nil || [[NCManageDatabase sharedInstance] isTableInvalidated:metadata]) {
        return [CCCellMain new];
    }
    
    tableDirectory *directory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.account, metadata.serverUrl]];
    if (directory != nil) {
        metadataFolder = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", directory.ocId]];
    }
    
    for (tableShare *share in appDelegate.shares) {
        if ([share.serverUrl isEqualToString:metadata.serverUrl] && [share.fileName isEqualToString:metadata.fileName]) {
            shareCell = share;
            break;
        }
    }
    
    UITableViewCell *cell = [[NCMainCommon sharedInstance] cellForRowAtIndexPath:indexPath tableView:tableView metadata:metadata metadataFolder:metadataFolder serverUrl:self.serverUrl autoUploadFileName:autoUploadFileName autoUploadDirectory:autoUploadDirectory tableShare:shareCell livePhoto:livePhoto];
    
    // NORMAL - > MAIN

    if ([cell isKindOfClass:[CCCellMain class]]) {
        
        // Comment tap
        if (metadata.commentsUnread) {
            UITapGestureRecognizer *tapComment = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapActionComment:)];
            [tapComment setNumberOfTapsRequired:1];
            ((CCCellMain *)cell).comment.userInteractionEnabled = YES;
            [((CCCellMain *)cell).comment addGestureRecognizer:tapComment];
        }
        
        // Share add Tap
        UITapGestureRecognizer *tapShare = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapActionShared:)];
        [tapShare setNumberOfTapsRequired:1];
        ((CCCellMain *)cell).viewShared.userInteractionEnabled = YES;
        [((CCCellMain *)cell).viewShared addGestureRecognizer:tapShare];
        
        // More
        if ([self canOpenMenuAction:metadata]) {
            
            UITapGestureRecognizer *tapMore = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(actionMore:)];
            [tapMore setNumberOfTapsRequired:1];
            ((CCCellMain *)cell).more.userInteractionEnabled = YES;
            [((CCCellMain *)cell).more addGestureRecognizer:tapMore];
        }
        
        // MGSwipeButton
        ((CCCellMain *)cell).delegate = self;
        
        // LEFT : configure ONLY Root Favorites : Remove file/folder Favorites
        if (_serverUrl == nil) {
            
            ((CCCellMain *)cell).leftButtons = @[[MGSwipeButton buttonWithTitle:@"" icon:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"favorite"] width:50 height:50 color:[UIColor whiteColor]] backgroundColor:NCBrandColor.sharedInstance.yellowFavorite padding:25]];
            ((CCCellMain *)cell).leftExpansion.buttonIndex = 0;
            ((CCCellMain *)cell).leftExpansion.fillOnTrigger = NO;
            
            //centerIconOverText
            MGSwipeButton *favoriteButton = (MGSwipeButton *)[((CCCellMain *)cell).leftButtons objectAtIndex:0];
            [favoriteButton centerIconOverText];
        }
        
        // RIGHT
        ((CCCellMain *)cell).rightButtons = @[[MGSwipeButton buttonWithTitle:@"" icon:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"trash"] width:50 height:50 color:[UIColor whiteColor]] backgroundColor:[UIColor redColor] padding:25]];
        
        ((CCCellMain *)cell).rightExpansion.buttonIndex = 0;
        ((CCCellMain *)cell).rightExpansion.fillOnTrigger = NO;
        
        //centerIconOverText
        MGSwipeButton *deleteButton = (MGSwipeButton *)[((CCCellMain *)cell).rightButtons objectAtIndex:0];
        [deleteButton centerIconOverText];
        
    }
    
    // TRANSFER
    
    if ([cell isKindOfClass:[CCCellMainTransfer class]]) {
        
        // gesture Transfer
        [((CCCellMainTransfer *)cell).transferButton.stopButton addTarget:self action:@selector(cancelTaskButton:withEvent:) forControlEvents:UIControlEventTouchUpInside];
        
        UILongPressGestureRecognizer *stopLongGesture = [UILongPressGestureRecognizer new];
        [stopLongGesture addTarget:self action:@selector(cancelAllTask:)];
        [((CCCellMainTransfer *)cell).transferButton.stopButton addGestureRecognizer:stopLongGesture];
    }
   
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // deselect row
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    self.metadata = [self setSelfMetadataFromIndexPath:indexPath];
    
    if (self.metadata.status != k_metadataStatusNormal && self.metadata.status != k_metadataStatusDownloadError) {
        return;
    }
    
    // File
    if (self.metadata.directory == NO) {
        
        // File do not exists
        if ([CCUtility fileProviderStorageExists:self.metadata.ocId fileNameView:self.metadata.fileNameView]) {
            
            [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadName:k_notificationCenter_downloadedFile object:nil userInfo:@{@"metadata": self.metadata, @"selector": selectorLoadFileView, @"errorCode": @(0), @"errorDescription": @""}];
                                        
        } else {
            
            tableDirectory *tableDirectory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.account, self.metadata.serverUrl]];
                
            if (tableDirectory.e2eEncrypted && ![CCUtility isEndToEndEnabled:appDelegate.account]) {
                    
                [[NCContentPresenter shared] messageNotification:@"_info_" description:@"_e2e_goto_settings_for_enable_" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:k_CCErrorInternalError forced:false];
                    
            } else {
                    
                if (([self.metadata.typeFile isEqualToString: k_metadataTypeFile_video] || [self.metadata.typeFile isEqualToString: k_metadataTypeFile_audio]) && self.metadata.e2eEncrypted == NO) {
                        
                    [self shouldPerformSegue:self.metadata selector:@""];
                
                } else if ([self.metadata.typeFile isEqualToString: k_metadataTypeFile_document] && [[NCUtility shared] isDirectEditingWithAccount:self.metadata.account contentType:self.metadata.contentType] != nil) {
                        
                        if (NCCommunication.shared.isNetworkReachable) {
                            [self shouldPerformSegue:self.metadata selector:@""];
                        } else {
                            [[NCContentPresenter shared] messageNotification:@"_info_" description:@"_go_online_" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:k_CCErrorInternalError forced:false];
                        }
                        
                    } else if ([self.metadata.typeFile isEqualToString: k_metadataTypeFile_document] && [[NCUtility shared] isRichDocument:self.metadata]) {
                        
                        if (NCCommunication.shared.isNetworkReachable) {
                            [self shouldPerformSegue:self.metadata selector:@""];
                        } else {
                            [[NCContentPresenter shared] messageNotification:@"_info_" description:@"_go_online_" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:k_CCErrorInternalError forced:false];
                        }
                        
                } else {
                        
                    if ([self.metadata.typeFile isEqualToString: k_metadataTypeFile_image]) {
                        [self shouldPerformSegue:self.metadata selector:selectorLoadFileView];
                    }
                    
                    [[NCNetworking shared] downloadWithMetadata:self.metadata selector:selectorLoadFileViewFavorite setFavorite:false completion:^(NSInteger errorCode) { }];
                }
            }
        }
    }
    
    // Directory
    if (self.metadata.directory) {
        
        CCFavorites *vc = [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:@"CCFavorites"];
        
        vc.serverUrl = [CCUtility stringAppendServerUrl:self.metadata.serverUrl addFileName:self.metadata.fileName];
        vc.titleViewControl = self.metadata.fileNameView;
        
        [self.navigationController pushViewController:vc animated:YES];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Navigation ====
#pragma --------------------------------------------------------------------------------------------

- (void)shouldPerformSegue:(tableMetadata *)metadata selector:(NSString *)selector
{
    // if i am in background -> exit
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) return;
    
    // if i am not window -> exit
    if (self.view.window == NO)
        return;
    
    // Collapsed but i am in detail -> exit
    if (self.splitViewController.isCollapsed) {
        if (appDelegate.activeDetail.isViewLoaded && appDelegate.activeDetail.view.window) return;
    }
    
    // Metadata for push detail
    self.metadataForPushDetail = metadata;
    self.selectorForPushDetail = selector;
    
    [self performSegueWithIdentifier:@"segueDetail" sender:self];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    UINavigationController *navigationController = segue.destinationViewController;
    NCDetailViewController *detailViewController = (NCDetailViewController *)navigationController.topViewController;
    
    NSMutableArray *photoDataSource = [NSMutableArray new];
    
    for (NSString *ocId in sectionDataSource.allOcId) {
        tableMetadata *metadata = [sectionDataSource.allRecordsDataSource objectForKey:ocId];
        if ([metadata.typeFile isEqualToString: k_metadataTypeFile_image])
            [photoDataSource addObject:metadata];
    }
    
    detailViewController.metadata = self.metadataForPushDetail;
    detailViewController.selector = self.selectorForPushDetail;
    
    [detailViewController setTitle:self.metadata.fileNameView];
}

@end
