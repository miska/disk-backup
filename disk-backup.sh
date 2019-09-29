#!/bin/sh
BCK_ST="/mnt/backup"
BCK_DIR="$BCK_ST/disk-backup"
BRANDING=""
MODE="backup"

cleanup() {
    umount -fl "$BCK_ST" 2> /dev/null
    fusermount -uz "$BCK_ST" 2> /dev/null
}

trap cleanup EXIT

die() {
    echo "$1" >&2
    exit 1
}

disk_info() {
    disk_size="`sfdisk -s "$1"`"
    disk_size="`expr $disk_size / 1024`"
    if [ "$disk_size" -lt 1024 ]; then
        disk_size="$disk_size MB"
    else
    	disk_size="`expr $disk_size / 1024`" 
    	if [ "$disk_size" -lt 1024 ]; then
            disk_size="$disk_size GB"
    	else
    	    disk_size="`expr $disk_size / 1024`" 
            disk_size="$disk_size TB"
	fi
    fi
    echo "$disk_size `blkid -o value -s LABEL "$1"`"
}

mount_bck() {
    mkdir -p "$BCK_ST"
    [ "`stat -c %m "$BCK_ST"`" = / ] || return 0
    devices="`blkid -o device -t TYPE="ntfs"`"
    for i in $devices; do
        set "$@" "$i" "`disk_info $i`"
    done
    if [ "$MODE" = backup ]; then
        text="Where do you want to save your backups?"
    else
        text="Where are your backups stored?"
    fi
    BCK_DEV="`dialog $BRANDING --menu "$text" -1 -1 \`echo $devices | wc -w\` "$@" 3>&1 1>&2 2>&3`"
    [ "$BCK_DEV" ] || die "No backup device selected"
    ntfs-3g "$BCK_DEV" "$BCK_ST" || die "Can't mount $BCK_DEV"
    mkdir -p "$BCK_DIR"
}

select_mode() {
    if dialog $BRANDING --yes-label Backup --no-label Restore --yesno "Do you want to backup your drives or restore them?" -1 -1; then
        MODE=backup
    else
        MODE=restore
    fi
}

ui_dd() {
    rm -f /tmp/progress
    echo "0" > /tmp/progress
    if [ -b "$1" ]; then
        total_size="`sfdisk -s "$1"`"
	total_size="`expr $total_size \* 1024`"
    else
        total_size="`du -b "$1" | sed 's|[[:blank:]].*||'`"
    fi
    tail -f /tmp/progress 2> /dev/null | dialog $BRANDING --gauge "$3" -1 -1 &
    dd if="$1" of="$2" bs=16M 2> /tmp/dd_progress &
    while killall -0 dd 2> /dev/null; do
        sleep 1
        killall -USR1 dd 2> /dev/null
        sleep 1
        current_size="`sed -n 's|\ bytes.*||p' /tmp/dd_progress | tail -n 1`"
        expr \( $current_size \* 100 \) / $total_size >> /tmp/progress
    done
    echo 100 >> /tmp/progress
    sync
    killall tail
}

backup() {
    disks="`ls -d /sys/class/block/*/device | sed 's|.*/\([^/]*\)/device|\1|'`"
    size="1"
    for i in $disks; do
        disk_meta="`cat /sys/block/$i/device/model | sed 's|[[:blank:]]*$||'`"
        parts="`ls -d /sys/class/block/$i/*/ro | sed 's|.*/\([^/]*\)/ro|\1|'`"
        set "$@" "$i-partition" "$disk_meta partition table" off
        size="`expr "$size" + 1`"
        for j in $parts; do
            size="`expr "$size" + 1`"
            set "$@" "$j" "`disk_info /dev/$j` $disk_meta" off
        done
    done
    TO_BCK="`dialog $BRANDING --checklist "What do you want to backup?" -1 -1 $size "$@" 3>&1 1>&2 2>&3`"
    for i in $TO_BCK; do
        if expr "$i" : ".*-partition" > /dev/null; then
            device="`echo "$i" | sed 's|-partition||'`"
            sfdisk --dump "/dev/$device" > "$BCK_DIR/$device.part"
        else
            ui_dd "/dev/$i" "$BCK_DIR/$i.raw" "Backing up $i - `disk_info "/dev/$i"`..."
        fi
    done
}

restore() {
    disks="`ls -d /sys/class/block/*/device | sed 's|.*/\([^/]*\)/device|\1|'`"
    size="1"
    for i in $disks; do
        disk_meta="`cat /sys/block/$i/device/model`"
        parts="`ls -d /sys/class/block/$i/*/ro | sed 's|.*/\([^/]*\)/ro|\1|'`"
        [ \! -f "$BCK_DIR/$i.part" ] || {
            set "$@" "$i-partition" "$disk_meta partition table" off
            size="`expr "$size" + 1`"
        }
        for j in $parts; do
            [ \! -f "$BCK_DIR/$j.raw" ] || {
                set "$@" "$j" "$disk_meta `disk_info /dev/$j`" off
                size="`expr "$size" + 1`"
            }
        done
    done
    TO_BCK="`dialog $BRANDING --checklist "What do you want to restore?" -1 -1 $size "$@" 3>&1 1>&2 2>&3`"
    for i in $TO_BCK; do
        if expr "$i" : ".*-partition" > /dev/null; then
            device="`echo "$i" | sed 's|-partition||'`"
            sfdisk "/dev/$device" < "$BCK_DIR/$device.part"
        else
            ui_dd "$BCK_DIR/$i.raw" "/dev/$i" "Restoring $i..."
        fi
    done
}

select_mode
mount_bck
if [ "$MODE" = backup ]; then
    backup
else
    restore
fi
clear
