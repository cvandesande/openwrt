#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=ask-cdx
PKG_VERSION:=5.03.1
PKG_RELEASE:=49

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/cvandesande/ask-cdx.git
# When PKG_SOURCE_VERSION changes, run this and update PKG_MIRROR_HASH:
#   scripts/mono-check-vendor-hashes.sh package/kernel/ask-cdx
PKG_SOURCE_VERSION:=c7e364d6655db25cb67c3b016cbbb9fdd74622b4
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.zst
PKG_MIRROR_HASH:=3a9e5f0b01720133a207336d012acbff23574b8e9992a2844b774e0c73bd185b
PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING.GPL

include $(INCLUDE_DIR)/package.mk

define KernelPackage/ask-cdx
  SUBMENU:=Network Devices
  TITLE:=NXP ASK CDX fast path module
  DEPENDS:=@TARGET_layerscape +kmod-ipsec4 +kmod-ipsec6
  FILES:=$(PKG_BUILD_DIR)/cdx-$(PKG_VERSION)/cdx.ko
  URL:=https://github.com/cvandesande/ask-cdx
endef

define KernelPackage/ask-cdx/description
  Control Data Exchange (CDX) kernel module providing fast path offload
  infrastructure for NXP Layerscape processors. Part of the Application
  Solutions Kit (ASK).
endef

CDX_DIR:=$(PKG_BUILD_DIR)/cdx-$(PKG_VERSION)

# Keep Stage 2 on the wired first-class only. WiFi stays deferred; this
# milestone compiles the IPsec hook points needed by ASK/CDX/CMM.
CDX_MAKE_OPTS:= \
	PLATFORM=LS1043A \
	KERNELDIR="$(LINUX_DIR)" \
	KERNEL_SRC="$(LINUX_DIR)" \
	CFG_FLAGS="-DSEC_PROFILE_SUPPORT -DVLAN_FILTER -DENABLE_EGRESS_QOS -DCONFIG_FSL_DPAA_ETH_REFILL_THRESHOLD=80 -DCONFIG_INET_IPSEC_OFFLOAD -DCONFIG_INET6_IPSEC_OFFLOAD"

define Build/Compile
	$(KERNEL_MAKE) \
		M="$(CDX_DIR)" \
		$(CDX_MAKE_OPTS) \
		modules
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/cdx
	$(CP) $(CDX_DIR)/Module.symvers $(1)/usr/include/cdx/Module.symvers
	$(CP) $(CDX_DIR)/cdx_ioctl.h $(1)/usr/include/cdx/
endef

define KernelPackage/ask-cdx/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/cdx.init $(1)/etc/init.d/cdx
endef

$(eval $(call KernelPackage,ask-cdx))
