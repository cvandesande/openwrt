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
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/cvandesande/fci.git
PKG_SOURCE_VERSION:=655983ec1e5bbc7c2892ac5c35fb431b97d05c00
PKG_SOURCE_SUBDIR:=fci-source-$(PKG_VERSION)
PKG_MIRROR_HASH:=65ebd6f2a97186e602fc47a50e40eb4f33f234f21273eabc877a6377b06d36f4
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
