#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=ask-fci
PKG_VERSION:=9.00.12
PKG_RELEASE:=4

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/cvandesande/fci.git
# When PKG_SOURCE_VERSION changes, run this and update PKG_MIRROR_HASH:
#   scripts/mono-check-vendor-hashes.sh package/kernel/ask-fci package/libs/libfci
PKG_SOURCE_VERSION:=8ddb017aaa6dc34edd54b890448434c1cb997561
PKG_SOURCE_SUBDIR:=fci-source-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.zst
PKG_MIRROR_HASH:=50b46cbc11f410d7a3f4345b1f9eb6777e8a2045308cd05561912430922a7099
PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING.GPL

include $(INCLUDE_DIR)/package.mk

define KernelPackage/ask-fci
  SUBMENU:=Network Devices
  TITLE:=NXP ASK FCI fast path control interface
  DEPENDS:=@TARGET_layerscape +kmod-ask-cdx
  FILES:=$(PKG_BUILD_DIR)/fci-$(PKG_VERSION)/fci.ko
  URL:=https://github.com/cvandesande/fci
endef

define KernelPackage/ask-fci/description
  Fast path Control Interface (FCI) kernel module for communication with
  the CMM daemon. Part of the NXP Application Solutions Kit (ASK).
endef

FCI_DIR:=$(PKG_BUILD_DIR)/fci-$(PKG_VERSION)

define Build/Compile
	$(KERNEL_MAKE) \
		M="$(FCI_DIR)" \
		BOARD_ARCH=arm64 \
		KBUILD_EXTRA_SYMBOLS="$(STAGING_DIR)/usr/include/cdx/Module.symvers" \
		modules
endef

define KernelPackage/ask-fci/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/fci.init $(1)/etc/init.d/fci
endef

$(eval $(call KernelPackage,ask-fci))
