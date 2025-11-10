Creates Backup
Compresses the target folder into a .tar.gz archive using tar.
Example filename: backup-2025-11-10-1215.tar.gz.


Generates Checksum
Uses sha256sum to create a fingerprint file (.sha256), ensuring data integrity.


Verifies Backup
Immediately re-checks the checksum to confirm the backup isn’t corrupted.


Deletes Old Backups
Removes backup files older than 7 days using the find command.


Logs Everything
All actions and results are written to backup.log.



⚠️ Error Handling


If the source folder doesn’t exist, the script stops with an error.


If checksum verification fails, it reports a “Checksum mismatch” and exits.


If there’s no disk space, tar will fail and log the error.



🧪 Testing Example
mkdir test_data
echo "hello world" > test_data/file1.txt
./backup.sh test_data

Output (in backup.log):
[2025-11-10 12:15:01] Starting backup of test_data
[2025-11-10 12:15:03] Backup created: backup-2025-11-10-1215.tar.gz
[2025-11-10 12:15:03] Verifying backup...
[2025-11-10 12:15:03] Verification successful.
[2025-11-10 12:15:03] Cleaning up backups older than 7 days...
[2025-11-10 12:15:03] Cleanup done.
[2025-11-10 12:15:03] SUCCESS: Backup complete ✅


🚀 Design Decisions


Simplicity first: Focused on required core features for grading.


Portability: Uses standard Linux commands (tar, sha256sum, find, date).


Reliability: Uses checksum verification to ensure backup integrity.



🧭 Known Limitations


No configuration file or email notifications.


Only supports one backup source at a time.


Keeps backups for a fixed 7 days (change KEEP_DAYS in script to adjust).


No dry-run or restore mode (for simplicity).



✅ Next Steps (Improvements)


Add a config file for settings like destination, exclusions, and retention.


Implement dry-run and restore options.


Add weekly/monthly rotation logic.



Would you like me to include this README.md in a ready-to-download ZIP with your backup.sh script and example folder structure?
