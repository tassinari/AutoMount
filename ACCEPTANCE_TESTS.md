# MagicMount — Main App Acceptance Test Plan (GWT)

## Context
Manual acceptance test plan for the MagicMount macOS main app covering all user-facing features. Tests are written in Given-When-Then format for manual QA execution. Requires a reachable SMB/AFP/NFS server on the local network.

---

## 1. Share List View

### 1.1 App launches with empty state
- **Given** no managed shares have been saved
- **When** the app launches
- **Then** the share list table is empty and the search bar and "+" button are visible

### 1.2 App launches with existing managed shares
- **Given** managed shares were previously saved
- **When** the app launches
- **Then** all managed shares appear in the table with correct name, type, mount point, and status

### 1.3 Refresh button reloads share list
- **Given** the app is running and shares are displayed
- **When** the user clicks the refresh button (↻)
- **Then** the share list reloads and reflects the current mount state of all shares

### 1.4 Search filters shares by name
- **Given** multiple shares are displayed (e.g. "MediaServer", "BackupNAS")
- **When** the user types "Media" in the search bar
- **Then** only shares matching "Media" in name, URL, or mount point are shown

### 1.5 Search is case-insensitive
- **Given** a share named "MediaServer" exists
- **When** the user types "media" (lowercase) in the search bar
- **Then** "MediaServer" is shown in the results

### 1.6 Clearing search restores full list
- **Given** search text is filtering the share list
- **When** the user clears the search field
- **Then** all shares are displayed again

### 1.7 Default sort is by Name ascending
- **Given** multiple shares exist with different names
- **When** the app launches
- **Then** the share list is sorted by Name in ascending (A–Z) order

### 1.8 Clicking a column header sorts by that column
- **Given** multiple shares are displayed
- **When** the user clicks the "Mount Point" column header
- **Then** the share list is sorted by mount point

### 1.9 Clicking the same column header toggles sort direction
- **Given** the share list is sorted by Name ascending
- **When** the user clicks the "Name" column header again
- **Then** the sort order reverses to descending (Z–A)

### 1.10 All columns are sortable
- **Given** multiple shares are displayed with varied values
- **When** the user clicks each column header (Managed, Name, Type, Mount Point, Status) in turn
- **Then** the list re-sorts by that column's values each time

---

## 2. Adding a Share

### 2.1 Open add dialog via button
- **Given** the main window is visible
- **When** the user clicks the "+" button
- **Then** the "New Connection" dialog appears with an empty URL field, "Always keep mounted" toggle ON, and Submit button disabled

### 2.2 Open add dialog via keyboard shortcut
- **Given** the main window is focused
- **When** the user presses Cmd+K
- **Then** the "New Connection" dialog appears

### 2.3 Submit button disabled when URL empty
- **Given** the add dialog is open
- **When** the URL field is empty
- **Then** the Submit button is disabled

### 2.4 Submit button enabled when URL entered
- **Given** the add dialog is open
- **When** the user types a URL (e.g. "smb://server/share")
- **Then** the Submit button becomes enabled

### 2.5 Successful mount with manage ON
- **Given** the add dialog is open with a valid, reachable SMB URL and "Always keep mounted" is ON
- **When** the user clicks Submit
- **Then** a progress spinner shows "Connecting...", the share mounts successfully, the dialog closes, and the share appears in the list as mounted and managed

### 2.6 Successful mount with manage OFF
- **Given** the add dialog is open with a valid, reachable URL and "Always keep mounted" is OFF
- **When** the user clicks Submit
- **Then** the share mounts successfully, the dialog closes, and the share appears as mounted but NOT managed

### 2.7 Cancel during mount operation
- **Given** the add dialog is showing "Connecting..." with spinner
- **When** the user clicks Cancel
- **Then** the mount operation is canceled and the dialog closes

### 2.8 Invalid URL shows error
- **Given** the add dialog is open
- **When** the user enters "not-a-url" and clicks Submit
- **Then** an alert displays "The URL is invalid." and the dialog remains open

### 2.9 Unreachable host shows error
- **Given** the add dialog is open
- **When** the user enters "smb://nonexistent.invalid/share" and clicks Submit
- **Then** an alert displays "Cannot find the server. Please check the address." and the dialog remains open for retry

### 2.10 Authentication failure shows error
- **Given** the add dialog is open with a valid server that requires credentials
- **When** the mount fails due to bad credentials
- **Then** an alert displays "Authentication failed. Please check your credentials."

### 2.11 Connection timeout shows error
- **Given** the add dialog is open with a server that is slow to respond
- **When** the connection times out
- **Then** an alert displays "The connection timed out."

### 2.12 Share not found shows error
- **Given** the add dialog is open
- **When** the user enters a valid server but invalid share path (e.g. "smb://server/nonexistent")
- **Then** an alert displays "The share was not found on the server."

### 2.13 Already mounted share shows error
- **Given** a share is already mounted
- **When** the user tries to add the same URL again
- **Then** an alert displays "This share is already mounted."

### 2.14 Server added to history on success
- **Given** the user successfully mounts "smb://newserver/share"
- **When** the user opens the add dialog again
- **Then** "smb://newserver/share" appears in the server combo box autocomplete list

### 2.15 Server NOT added to history on failure
- **Given** the user attempts to mount an unreachable server
- **When** the mount fails
- **Then** the server URL is NOT added to the history autocomplete list

---

## 3. Mount / Unmount Operations

### 3.1 Mount an unmounted share
- **Given** an unmounted managed share is displayed in the list
- **When** the user clicks the mount button (arrow icon) on that share
- **Then** a progress spinner appears, the share mounts, and the status changes to green (mounted)

### 3.2 Unmount a mounted share
- **Given** a mounted share is displayed in the list
- **When** the user clicks the eject button on that share
- **Then** a progress spinner appears, the share unmounts, and the status changes to gray (unmounted)

### 3.3 Open mounted share in Finder
- **Given** a share is mounted and shows a mount point path
- **When** the user clicks the mount point link
- **Then** Finder opens showing the contents of that mount point

### 3.4 Mount point not clickable when unmounted
- **Given** a share is unmounted
- **When** the user views the mount point column
- **Then** the mount point text is not clickable / not a link

### 3.5 Progress indicator during mount
- **Given** a mount operation is in progress
- **When** the user looks at the share row
- **Then** a spinning progress indicator replaces the mount/unmount button

### 3.6 Progress indicator during unmount
- **Given** an unmount operation is in progress
- **When** the user looks at the share row
- **Then** a spinning progress indicator replaces the mount/unmount button

---

## 4. Managed Toggle

### 4.1 Toggle share to managed
- **Given** an unmanaged share is displayed
- **When** the user toggles the "Managed" switch ON
- **Then** the share is saved to persistent storage for auto-remount by the background service

### 4.2 Toggle share to unmanaged
- **Given** a managed share is displayed
- **When** the user toggles the "Managed" switch OFF
- **Then** the share is removed from persistent storage and will no longer auto-remount

---

## 5. Protocol Support

### 5.1 Mount SMB share
- **Given** the add dialog is open
- **When** the user enters "smb://server/share" and submits
- **Then** the share mounts via SMB and the Type column shows "SMB"

### 5.2 Mount AFP share
- **Given** the add dialog is open
- **When** the user enters "afp://server/share" and submits
- **Then** the share mounts via AFP and the Type column shows "AFP"

### 5.3 Mount NFS share
- **Given** the add dialog is open
- **When** the user enters "nfs://server/export" and submits
- **Then** the share mounts via NFS and the Type column shows "NFS"

---

## 6. Settings

### 6.1 Open settings
- **Given** the app is running
- **When** the user presses Cmd+, (or uses the menu)
- **Then** the Settings window appears with Settings and About tabs

### 6.2 Toggle "Show in menu bar"
- **Given** the Settings window is open on the Settings tab
- **When** the user toggles "Show in menu bar" OFF
- **Then** the MagicMountBackground menu bar icon is hidden

### 6.3 Toggle "Show in menu bar" back on
- **Given** "Show in menu bar" is OFF
- **When** the user toggles it ON
- **Then** the MagicMountBackground menu bar icon reappears

### 6.4 Clear previous servers
- **Given** server history contains previously used URLs
- **When** the user clicks "Clear previous servers"
- **Then** the autocomplete history in the add dialog is empty

### 6.5 Network debounce picker shows preset values
- **Given** the Settings window is open
- **When** the user opens the "Network debounce" picker
- **Then** the options are 5 seconds, 15 seconds, 30 seconds, 60 seconds; default is 15 seconds

### 6.6 Selecting a debounce value persists
- **Given** the Settings window is open
- **When** the user selects a network debounce value (e.g. 30 seconds)
- **Then** the value persists and is used by the background service

### 6.7 Periodic remount picker shows preset values
- **Given** the Settings window is open
- **When** the user opens the "Periodic remount" picker
- **Then** the options are Off, 1 minute, 5 minutes, 15 minutes, 1 hour; default is 5 minutes

### 6.8 Selecting "Off" disables periodic remount
- **Given** the Settings window is open
- **When** the user selects "Off" for periodic remount
- **Then** the periodic remount timer is disabled and no automatic remounts occur on a schedule

### 6.9 Selecting a periodic remount value persists
- **Given** the Settings window is open
- **When** the user selects a periodic remount value (e.g. 15 minutes)
- **Then** the value persists and is used by the background service

### 6.10 About tab displays app info
- **Given** the Settings window is open
- **When** the user clicks the About tab
- **Then** "Magic Mount" title and "by Mark Tassinari" are displayed

---

## 7. Background Service / Login Item

### 7.1 Warning banner when service disabled
- **Given** the background service (login item) is not enabled
- **When** the app launches
- **Then** an orange warning banner is displayed indicating the background service is disabled

### 7.2 No warning banner when service enabled
- **Given** the background service (login item) is enabled
- **When** the app launches
- **Then** no warning banner is displayed

### 7.3 Warning banner links to help
- **Given** the warning banner is displayed
- **When** the user clicks the link on the banner
- **Then** the Help window opens

### 7.4 Login item status refreshes on app activate
- **Given** the user enables the login item in System Settings while MagicMount is in the background
- **When** the user switches back to MagicMount
- **Then** the warning banner disappears and `isLoginItemEnabled` is true

---

## 8. Help

### 8.1 Open help via keyboard shortcut
- **Given** the app is running
- **When** the user presses Cmd+?
- **Then** the Help window opens with documentation content

### 8.2 Open help via menu
- **Given** the app is running
- **When** the user clicks Help → MagicMount Help
- **Then** the Help window opens

### 8.3 Help content is readable
- **Given** the Help window is open
- **When** the user scrolls through the content
- **Then** sections on Getting Started, Adding a Share, Protocols, Mounting, Settings, FAQ, and Troubleshooting are all present and readable

---

## 9. System Integration

### 9.1 External mount detected
- **Given** the app is running
- **When** a network volume is mounted externally (e.g. via Finder "Connect to Server")
- **Then** the share list updates to show the newly mounted volume

### 9.2 External unmount detected
- **Given** a share is shown as mounted in the app
- **When** the volume is unmounted externally (e.g. via Finder eject)
- **Then** the share list updates to reflect the unmounted status

### 9.3 Shared data with background service
- **Given** the main app and background service are both running
- **When** the user adds a managed share in the main app
- **Then** the background service picks up the new share for auto-remount

---

## 10. Window Behavior

### 10.1 Minimum window size enforced
- **Given** the main window is displayed
- **When** the user tries to resize it smaller than 750×400px
- **Then** the window stops at the minimum size

### 10.2 Settings window is fixed size
- **Given** the Settings window is open
- **When** the user tries to resize it
- **Then** the window remains at 300×200px (non-resizable)
