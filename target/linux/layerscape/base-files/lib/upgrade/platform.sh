#
# Copyright 2015-2019 Traverse Technologies
# Copyright 2020 NXP
#

RAMFS_COPY_BIN=""
RAMFS_COPY_DATA=""

REQUIRE_IMAGE_METADATA=1

MONO_ROOT_START_SECTOR=65536

mono_cmdline_get_var() {
	local key="$1"
	local arg

	for arg in $(cat /proc/cmdline); do
		case "$arg" in
		${key}=*)
			echo "${arg#*=}"
			return 0
			;;
		esac
	done

	return 1
}

mono_gateway_root_part() {
	local root part disk partn start removable type

	if ! grep -q "mono,gateway-dk" /sys/firmware/devicetree/base/compatible 2>/dev/null; then
		echo "Not a Mono Gateway DK" >&2
		return 1
	fi

	root="$(mono_cmdline_get_var root)" || {
		echo "Unable to determine root device" >&2
		return 1
	}

	case "$root" in
	/dev/mmcblk*p1)
		part="${root##*/}"
		;;
	*)
		echo "Refusing to use unsupported root device: $root" >&2
		return 1
		;;
	esac

	disk="${part%p1}"
	case "$disk" in
	mmcblk|mmcblk*[!0-9]*)
		echo "Refusing to use non-eMMC root device: /dev/$part" >&2
		return 1
		;;
	esac

	[ -b "/dev/$part" ] || {
		echo "Root partition /dev/$part is not a block device" >&2
		return 1
	}

	[ -d "/sys/block/$disk" ] || {
		echo "Root disk /dev/$disk is not present" >&2
		return 1
	}

	partn="$(cat "/sys/class/block/$part/partition" 2>/dev/null)"
	[ "$partn" = "1" ] || {
		echo "Refusing to use non-root partition /dev/$part" >&2
		return 1
	}

	start="$(cat "/sys/class/block/$part/start" 2>/dev/null)"
	[ "$start" = "$MONO_ROOT_START_SECTOR" ] || {
		echo "Refusing to use /dev/$part: start sector is $start, expected $MONO_ROOT_START_SECTOR" >&2
		return 1
	}

	removable="$(cat "/sys/block/$disk/removable" 2>/dev/null)"
	[ "$removable" = "0" ] || {
		echo "Refusing to use removable root disk /dev/$disk" >&2
		return 1
	}

	type="$(cat "/sys/block/$disk/device/type" 2>/dev/null)"
	[ "$type" = "MMC" ] || {
		echo "Refusing to use non-eMMC root disk /dev/$disk" >&2
		return 1
	}

	echo "/dev/$part"
}

platform_do_upgrade_sdboot() {
	local diskdev partdev parttype=ext4
	local tar_file="$1"
	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	if export_partdevice partdev 1; then
		mount -t $parttype -o rw,noatime "/dev/$partdev" /mnt 2>&1
		echo "Writing kernel..."
		tar xf $tar_file ${board_dir}/kernel -O > /mnt/fitImage
		umount /mnt
	fi

	echo "Erasing rootfs..."
	dd if=/dev/zero of=/dev/mmcblk0p2 bs=1M > /dev/null 2>&1
	echo "Writing rootfs..."
	tar xf $tar_file ${board_dir}/root -O  | dd of=/dev/mmcblk0p2 bs=512k > /dev/null 2>&1

}

platform_do_upgrade_emmc() {
	local image_file="$1"
	local rootpart

	rootpart="$(mono_gateway_root_part)" || return 1

	echo "Writing image to $rootpart..."
	get_image "$image_file" | fwtool -i /dev/null -T - | dd of="$rootpart" bs=512k conv=fsync || {
		echo "Image write to $rootpart failed"
		return 1
	}
	echo "Upgrade complete"
}

platform_do_upgrade_traverse_slotubi() {
	part="$(awk -F 'ubi.mtd=' '{printf $2}' /proc/cmdline | sed -e 's/ .*$//')"
	echo "Active boot slot: ${part}"
	new_active_sys="b"

	if [ ! -z "${part}" ]; then
		if [ "${part}" = "ubia" ]; then
			CI_UBIPART="ubib"
		else
			CI_UBIPART="ubia"
			new_active_sys="a"
		fi
	fi
	echo "Updating UBI part ${CI_UBIPART}"
	fw_setenv "openwrt_active_sys" "${new_active_sys}"
	nand_do_upgrade "$1"
	return $?
}

platform_copy_config_sdboot() {
	local diskdev partdev parttype=ext4

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	if export_partdevice partdev 1; then
		mount -t $parttype -o rw,noatime "/dev/$partdev" /mnt 2>&1
		echo "Saving config backup..."
		cp -af "$UPGRADE_BACKUP" "/mnt/$BACKUP_FILE"
		umount /mnt
	fi
}
platform_copy_config_emmc() {
	local rootpart

	rootpart="$(mono_gateway_root_part)" || return 1

	mount -t ext4 -o rw,noatime "$rootpart" /mnt 2>&1 || {
		echo "Failed to mount $rootpart for config backup"
		return 1
	}

	echo "Saving config backup..."
	cp -af "$UPGRADE_BACKUP" "/mnt/$BACKUP_FILE" || {
		echo "Failed to copy config backup to $rootpart"
		umount /mnt
		return 1
	}

	umount /mnt || {
		echo "Failed to unmount $rootpart after config backup"
		return 1
	}
}

platform_copy_config() {
	local board=$(board_name)

	case "$board" in
	fsl,ls1012a-frwy-sdboot | \
	fsl,ls1021a-iot-sdboot | \
	fsl,ls1021a-twr-sdboot | \
	fsl,ls1028a-rdb-sdboot | \
	fsl,ls1043a-rdb-sdboot | \
	fsl,ls1046a-frwy-sdboot | \
	fsl,ls1046a-rdb-sdboot | \
	fsl,ls1088a-rdb-sdboot | \
	fsl,lx2160a-rdb-sdboot)
		platform_copy_config_sdboot
		;;
	mono,gateway-dk | \
	mono,gateway-dk-sdboot)
		platform_copy_config_emmc
		;;
	esac
}
platform_check_image() {
	local board=$(board_name)

	case "$board" in
	traverse,ten64)
		nand_do_platform_check "ten64-mtd" $1
		return $?
		;;
	fsl,ls1012a-frdm | \
	fsl,ls1012a-frwy-sdboot | \
	fsl,ls1012a-rdb | \
	fsl,ls1021a-iot-sdboot | \
	fsl,ls1021a-twr | \
	fsl,ls1021a-twr-sdboot | \
	fsl,ls1028a-rdb | \
	fsl,ls1028a-rdb-sdboot | \
	fsl,ls1043a-rdb | \
	fsl,ls1043a-rdb-sdboot | \
	fsl,ls1046a-frwy | \
	fsl,ls1046a-frwy-sdboot | \
	fsl,ls1046a-rdb | \
	fsl,ls1046a-rdb-sdboot | \
	fsl,ls1088a-rdb | \
	fsl,ls1088a-rdb-sdboot | \
	fsl,ls2088a-rdb | \
	fsl,lx2160a-rdb | \
	fsl,lx2160a-rdb-sdboot | \
	mono,gateway-dk | \
	mono,gateway-dk-sdboot)
		return 0
		;;
	*)
		echo "Sysupgrade is not currently supported on $board"
		;;
	esac

	return 1
}
platform_do_upgrade() {
	local board=$(board_name)

	# Force the creation of fw_printenv.lock
	mkdir -p /var/lock
	touch /var/lock/fw_printenv.lock

	case "$board" in
	traverse,ten64)
		platform_do_upgrade_traverse_slotubi "${1}"
		;;
	fsl,ls1012a-frdm | \
	fsl,ls1012a-rdb | \
	fsl,ls1021a-twr | \
	fsl,ls1028a-rdb | \
	fsl,ls1043a-rdb | \
	fsl,ls1046a-frwy | \
	fsl,ls1046a-rdb | \
	fsl,ls1088a-rdb | \
	fsl,ls2088a-rdb | \
	fsl,lx2160a-rdb)
		PART_NAME=firmware
		default_do_upgrade "$1"
		;;
	fsl,ls1012a-frwy-sdboot | \
	fsl,ls1021a-iot-sdboot | \
	fsl,ls1021a-twr-sdboot | \
	fsl,ls1028a-rdb-sdboot | \
	fsl,ls1043a-rdb-sdboot | \
	fsl,ls1046a-frwy-sdboot | \
	fsl,ls1046a-rdb-sdboot | \
	fsl,ls1088a-rdb-sdboot | \
	fsl,lx2160a-rdb-sdboot)
		platform_do_upgrade_sdboot "$1"
		return 0
		;;
	mono,gateway-dk | \
	mono,gateway-dk-sdboot)
		platform_do_upgrade_emmc "$1"
		return $?
		;;
	*)
		echo "Sysupgrade is not currently supported on $board"
		;;
	esac
}
