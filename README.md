

---

# **Automated Backup System – README**

## **Project Name:** Automated Backup System

## **Overview**

The **Automated Backup System** is a Bash-based automation tool designed to securely back up important files and manage them efficiently. It supports full and incremental backups, integrity checking, automatic cleanup, and restoration — helping protect your data with minimal manual intervention.

This script can:

* Automatically back up your selected directories
* Perform both **full** and **incremental** backups
* Remove old backups using a rotation policy
* Validate each backup using **SHA256 checksum**
* Simulate email notifications
* Provide **dry-run**, **list**, and **restore** options

This system reduces manual work, improves data safety, and keeps storage organized.

---

# **Main Features and Functions**

## **1. Configuration Loader**

```bash
CONFIG_FILE="./backup.config"
source "$CONFIG_FILE"
```

All configurable values—backup destination, retention policy, log file location, exclusion patterns—are stored in `backup.config` for easy modification without editing the main script.

---

## **2. Logging System**

```bash
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
```

Every operation is recorded into `backup.log` with timestamps.
This helps with debugging and tracking backup history.

---

## **3. Prevent Multiple Simultaneous Runs**

Uses a lock file to avoid parallel backups:

```bash
if [[ -f "$LOCK_FILE" ]]; then
  echo "Another backup process is already running."
  exit 1
fi
```

This ensures safe and predictable execution.

---

## **4. Disk Space Verification**

Before creating a backup, the script checks whether enough disk space is available:

```bash
available=$(df --output=avail -k "$BACKUP_DESTINATION" | tail -1)
required=$(du -sk "$SOURCE_DIR" | awk '{print $1}')
```

If space is insufficient, the backup aborts safely.

---

## **5. Backup Creation (Core Feature)**

### **How Backups Work:**

Uses `tar` to create:

* **Full backups** → First run or on demand
* **Incremental backups** → Saves only changed files by using `backup.snar`

Example command:

```bash
tar --listed-incremental=backup.snar -czf backup-YYYY-MM-DD-HHMM.tar.gz "$SOURCE_DIR"
```

Backups are stored with timestamped names like:

```
backup-2025-11-04-0857.tar.gz
```

Supports **dry-run mode** to simulate operations without creating files.

---

## **6. Checksum Generation & Validation**

The script generates a checksum file for each backup:

```bash
sha256sum "$backup_name" > "$checksum_file"
```

To verify:

```bash
sha256sum -c "$file.sha256"
```

This ensures the backup is intact and unmodified.

---

## **7. Automatic Old Backup Deletion (Rotation System)**

The rotation system organizes backups into:

* **Daily backups**
* **Weekly backups**
* **Monthly backups**

Config example from `backup.config`:

```
DAILY_KEEP=7
WEEKLY_KEEP=4
MONTHLY_KEEP=3
```

Example logic:

```bash
daily_backups=($(ls -1t backup-*.tar.gz | head -n "$DAILY_KEEP"))
weekly_backups=($(find . -type f -name "backup-*.tar.gz" -mtime -28 -printf "%f\n"))
monthly_backups=($(find . -type f -name "backup-*.tar.gz" -mtime +28 -printf "%f\n"))
```

Backups older than 28 days (or outside retention settings) are deleted automatically:

```bash
find . -type f -name "backup-*.tar.gz" -mtime +28 -delete
```

### **Why This Is Useful**

* Prevents clutter
* Saves disk space
* Ensures consistent retention of recent backups

---

## **8. List All Available Backups**

Displays readable list:

```bash
ls -lh "$BACKUP_DESTINATION"/backup-*.tar.gz
```

Useful for seeing backup sizes and timestamps.

---

## **9. Restore Backups**

Restores archived backups into a chosen directory:

```bash
tar -xzf "$BACKUP_DESTINATION/$backup_file" -C "$restore_dir"
```

Allows complete recovery of data.

---

## **10. Email Notification (Simulated)**

Instead of sending real emails, actions are logged into `email.txt`:

```
Email simulated: Backup Success
```

---

# **Additional Features**

### **Dry Run Mode**

```
./backup.sh --dry-run /path/to/source
```

Simulates all backup steps without creating any file.

### **Error Handling**

The script gracefully exits on:

* Missing source directory
* Missing configuration file
* Insufficient disk space
* Invalid arguments

### **Incremental Backup Support**

Uses `.snar` file to track modified or new files.

### **Exclusion Support**

Excludes patterns like:

```
EXCLUDE_PATTERNS=".git,node_modules,.cache"
```

---

# **How It Works (Internal Logic)**

1. Load values from `backup.config`
2. Create lock file
3. Validate disk space
4. Create either full or incremental backup
5. Generate checksum
6. Verify checksum
7. Apply rotation policy to delete old backups
8. Create email notification
9. Log all operations
10. Remove lock file

---

# **Backup Rotation Logic Explained**

The script categorizes backups based on their age:

### **1. Daily backups**

* Keeps latest *N* backups (example: 7)

### **2. Weekly backups**

* Keeps one recent backup from each week

### **3. Monthly backups**

* Keeps one backup for each older month

Backups older than defined limits are safely deleted.

Example cleanup log:

```
[2025-11-04 08:57:54] Cleaning old backups...
[2025-11-04 08:57:54] Deleted old backup: backup-2025-09-01-0930.tar.gz
```

---

# **Checksum System Explained**

### **1. Checksum Creation**

After backup:

```
sha256sum backup.tar.gz > backup.tar.gz.sha256
```

### **2. Verification**

```
sha256sum -c backup.tar.gz.sha256
```

If hashes match → backup is valid
If not → script reports corruption

Example:

```
[2025-11-04 09:10:33] Checksum verified successfully
```

---

# **Project Structure**

```
backup/
├── backup.sh
├── backup.config
├── backup.log
├── email.txt
├── restore/
├── backupfiles/
│   ├── backup-2025-11-04-0857.tar.gz
│   ├── backup-2025-11-04-0857.tar.gz.sha256
│   └── backup.snar
└── SOURCE/
    ├── a.txt
    ├── b.txt
    └── notes.txt
```

---

# **Testing**

### **Tests Performed**

| Test Case          | Result                      |
| ------------------ | --------------------------- |
| Full backup        | Successful                  |
| Incremental backup | Working correctly           |
| Dry run            | Logs only, no files created |
| Low disk space     | Script exited safely        |
| Restore test       | Files restored properly     |
| Rotation cleanup   | Old backups deleted         |
| Invalid path test  | Error shown, script exited  |

### **Sample Output Log**

```
[2025-11-04 08:57:53] INFO: Starting backup...
[2025-11-04 08:57:54] SUCCESS: Backup created: backup-2025-11-04-0857.tar.gz
[2025-11-04 08:57:54] INFO: Checksum verified
[2025-11-04 08:57:54] Simulated Email: Backup Success
[2025-11-04 08:57:54] Cleaning old backups...
```

---

# **Approach**

A modular design is used, with separate functions for each part of the workflow:

* `create_backup`
* `verify_backup`
* `delete_old_backups`
* `restore_backup`
* `list_backups`

Using a config file avoids hardcoding values.

---

# **Challenges Faced**

* Handling full + incremental backup logic
* Ensuring rotation system works correctly
* Validating backup integrity
* Managing errors without script breaking

---

# **Solutions Implemented**

* SHA256 checksum validation
* Lock file to prevent multiple runs
* Config-based architecture
* Detailed logging for every action

---

# **Limitations**

* Does not send real emails (simulated only)
* No graphical interface
* No encryption of backups
* Restore requires valid `.tar.gz` file

---

# **Future Improvements**

* Add real email alerts (SMTP)
* Add cloud support (AWS S3 / Google Drive)
* Implement encryption (GPG)
* Add scheduling via cron
* Create GUI or web dashboard

---

# **Conclusion**

This Automated Backup System handles the complete backup lifecycle using pure Bash — creation, verification, cleanup, rotation, and restoration.
It demonstrates strong knowledge of scripting, automation, system management, and data protection.

---

