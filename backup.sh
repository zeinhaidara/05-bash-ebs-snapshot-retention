#!/usr/bin/env bash
# EBS snapshot backup and retention prune. See README.md.
set -euo pipefail

TAG=ebs-backup-script

usage() {
  echo "usage: backup.sh snapshot --region R"
  echo "       backup.sh prune --region R [--retention-days N] [--execute] [--force-short-retention]"
  exit 2
}

if ! command -v aws >/dev/null; then
  echo "aws CLI not found. Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
  exit 1
fi

[ $# -ge 1 ] || usage
cmd=$1
shift

region=""
retention=30
execute=0
force=0
while [ $# -gt 0 ]; do
  case $1 in
    --region) region=${2:?--region needs a value}; shift ;;
    --retention-days) retention=${2:?--retention-days needs a value}; shift ;;
    --execute) execute=1 ;;
    --force-short-retention) force=1 ;;
    *) usage ;;
  esac
  shift
done
[ -n "$region" ] || usage

ec2() { aws ec2 --region "$region" "$@"; }

snapshot() {
  local failed=0 vol inst state snap
  local today
  today=$(date -u +%Y-%m-%d)
  # one "volume instance" pair per line
  while read -r vol inst; do
    [ -n "$vol" ] || continue
    state=$(ec2 describe-instances --instance-ids "$inst" \
      --query 'Reservations[].Instances[].State.Name' --output text)
    if [ "$state" != running ]; then
      echo "skip $vol: instance $inst is $state"
      continue
    fi
    if snap=$(ec2 create-snapshot --volume-id "$vol" --query SnapshotId --output text \
      --tag-specifications "ResourceType=snapshot,Tags=[{Key=created-by,Value=$TAG},{Key=source-volume,Value=$vol},{Key=Name,Value=backup-$vol-$today}]"); then
      echo "created $snap from $vol"
    else
      echo "FAILED snapshot for $vol" >&2
      failed=1
    fi
  done < <(ec2 describe-volumes \
    --filters Name=tag:Backup,Values=true Name=attachment.status,Values=attached \
    --query 'Volumes[].[VolumeId,Attachments[0].InstanceId]' --output text)
  return "$failed"
}

prune() {
  if [ "$retention" -lt 7 ] && [ "$force" -eq 0 ]; then
    echo "retention below 7 days refused; add --force-short-retention to override" >&2
    exit 1
  fi
  local cutoff id started failed=0
  cutoff=$(date -u -d "$retention days ago" +%Y-%m-%dT%H:%M:%S)
  [ "$execute" -eq 1 ] || echo "dry run (add --execute to delete)"
  while read -r id started; do
    [ -n "$id" ] || continue
    # StartTime is ISO 8601 UTC, so plain string compare works
    [[ "$started" < "$cutoff" ]] || continue
    if [ "$execute" -eq 1 ]; then
      if ec2 delete-snapshot --snapshot-id "$id"; then
        echo "deleted $id ($started)"
      else
        echo "FAILED delete $id" >&2
        failed=1
      fi
    else
      echo "would delete $id ($started)"
    fi
  done < <(ec2 describe-snapshots --owner-ids self \
    --filters "Name=tag:created-by,Values=$TAG" \
    --query 'Snapshots[].[SnapshotId,StartTime]' --output text)
  return "$failed"
}

case $cmd in
  snapshot) snapshot ;;
  prune) prune ;;
  *) usage ;;
esac
