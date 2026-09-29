# DriveSync

A scheduled backup tool for macOS. Point it at a folder, point it at somewhere else, and it keeps the second one current.

Built on rsync, which ships inside the app — there's nothing else to install.

---

## What it does

- **Scheduled backups.** Set one or more times a day. DriveSync runs in the background whether or not the app is open.
- **Exclusions.** Skip folders or files you don't want copied, configured during setup or any time after.
- **Issue reporting.** Permission failures, a full destination, interrupted transfers — each is recorded with the path, the rsync exit code, and a link to the log.
- **Stale detection.** If no backup has succeeded within your threshold, DriveSync tells you instead of quietly doing nothing.
- **Menu bar status.** Current state at a glance, with manual run and stop.
- **Logs.** Every run is logged, with automatic cleanup after a retention period you set.
- **Update notifications.** Checks GitHub Releases and tells you when a newer version exists.

## Requirements

macOS 26.5 or later.

## Installing

Download the latest `DriveSync.pkg` from [Releases](../../releases) and open it.

macOS will warn that the package is from an unidentified developer. Right-click the file, choose **Open**, then **Open** again.

The installer places DriveSync and its uninstaller in `/Applications/DriveSync/`.

### First run

Setup asks for a source folder, a destination folder, and any exclusions. When you finish, DriveSync verifies it can read the source and write to the destination — and macOS asks permission for both while you're still there to answer.

This is deliberate. Those permission prompts would otherwise appear during the first scheduled backup, possibly in the middle of the night with nobody at the keyboard.

## How it works

DriveSync is a SwiftUI app that manages two launchd agents:

| Agent | Purpose |
|---|---|
| `com.drivesync.sync` | Runs the backup at your scheduled times |
| `com.drivesync.health` | Daily check for a stale backup |

Both invoke the same bundled shell script, which drives the bundled `rsync`. The app writes the configuration and the agents; the agents do the work. This means backups continue on schedule whether or not the app is running.

Backups use `--archive` with extended attributes and ACLs preserved, and are **additive** — files removed from the source are not removed from the destination.

### Where things live

```
/Applications/DriveSync/
    DriveSync.app
    DriveSync Uninstaller.app

~/Library/Application Support/DriveSync/
    config/
        config.plist          Source, destination, schedule, thresholds
        exclusions-user       Your exclusion patterns
    logs/                     One log per run
        health/               Health check logs
    state/                    Last success, current issues, run locks

~/Library/LaunchAgents/
    com.drivesync.sync.plist
    com.drivesync.health.plist
```

## Settings

| Setting | Default | What it controls |
|---|---|---|
| Schedule times | 12:00 AM | When backups run |
| Schedule window | 30 minutes | How long after a scheduled time a run may still start |
| Log retention | 90 days | How long logs are kept |
| Stale threshold | 14 days | How old the last success can get before you're warned |

The schedule window exists because a Mac that's asleep at the scheduled time runs the job when it wakes. The window stops a machine that's been off for a week from firing every missed backup at once.

## Troubleshooting

**Backups aren't running.** Check that Automatic Syncing is on in the main window. Settings → Diagnostics has a repair action that reinstalls the launch agents.

**Permission errors after moving folders.** Re-run setup so DriveSync can request access to the new locations.

**A network destination stopped working.** Mount points change. If you remount a share under a different name, the recorded path no longer resolves — re-run setup and choose the folder at its current location.

**Nothing is notifying me.** DriveSync opens at login so it can deliver notifications from background runs. If you've disabled that in System Settings → General → Login Items, failures will be recorded in the app but won't reach you.

## Uninstalling

**Help → Uninstall DriveSync…** from inside the app. This removes the app, its launch agents, its privileged helper, and optionally your configuration and logs.

## Building from source

Requires Xcode 26 or later.

1. Open `DriveSync/DriveSync.xcodeproj`
2. **Product → Archive**
3. Run `./Installer/build-installer.sh`

The build script packages the most recent archive, not your working tree — archive first, or you'll ship stale code. The finished package lands at `Installer/build/DriveSync.pkg`.
