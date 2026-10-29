# ebs-snapshot-retention

## Problem
Backups that nobody runs, and snapshot sprawl that nobody cleans up.

## Flow
1. Find volumes tagged `Backup=true` that are attached to a running instance.
2. Snapshot each one and tag the snapshot (`created-by=ebs-backup-script`, `source-volume`, `Name`).
3. Prune only the snapshots this script made, once they are older than the retention period.

## Usage
```
./backup.sh snapshot --region us-east-1
./backup.sh prune --region us-east-1 --retention-days 30             # dry run
./backup.sh prune --region us-east-1 --retention-days 30 --execute   # really delete
```
Retention defaults to 30 days. Below 7 days is refused unless you add `--force-short-retention`.
`snapshot` keeps going if one volume fails, and exits non-zero at the end.

Needs bash, GNU `date` and the AWS CLI. Tests run without AWS: `bash test/run.sh`.

## Safety
- `prune` is a dry run unless `--execute` is passed.
- `prune` lists only snapshots owned by you with the tag `created-by=ebs-backup-script`.
- `snapshot` never deletes anything.

## IAM policy for a scheduler role
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumes",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:CreateSnapshot",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:DeleteSnapshot",
      "Resource": "arn:aws:ec2:us-east-1::snapshot/*",
      "Condition": {
        "StringEquals": { "aws:ResourceTag/created-by": "ebs-backup-script" }
      }
    }
  ]
}
```
The condition on `DeleteSnapshot` is written from memory of the IAM docs. I could not verify the syntax without AWS, so test it in a sandbox account before relying on it.

## Limits
- No cross-region copy and no cross-account.
- A volume must be attached to a running instance to be picked up.
- Snapshot age uses `StartTime`.
- No backup verification: the script does not check that a snapshot completed or can be restored.
- Uses GNU `date`, so it runs on Linux, not stock macOS.
