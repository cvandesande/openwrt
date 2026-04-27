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
PKG_RELEASE:=8

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/cvandesande/ask-cdx.git
# When PKG_SOURCE_VERSION changes, run this and update PKG_MIRROR_HASH:
#   scripts/mono-check-vendor-hashes.sh package/kernel/ask-cdx
PKG_SOURCE_VERSION:=5338b8671ed8870515b4b31009a16d1d2bdddb6f
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.zst
PKG_MIRROR_HASH:=4cbafc0c5337ebaf68ece9ebe72c3c79d83465eb50a1fa99e063fa041a7ad2a9
PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING.GPL

include $(INCLUDE_DIR)/package.mk

define KernelPackage/ask-cdx
  SUBMENU:=Network Devices
  TITLE:=NXP ASK CDX fast path module
  DEPENDS:=@TARGET_layerscape
  FILES:=$(PKG_BUILD_DIR)/cdx-$(PKG_VERSION)/cdx.ko
  URL:=https://github.com/cvandesande/ask-cdx
endef

define KernelPackage/ask-cdx/description
  Control Data Exchange (CDX) kernel module providing fast path offload
  infrastructure for NXP Layerscape processors. Part of the Application
  Solutions Kit (ASK).
endef

CDX_DIR:=$(PKG_BUILD_DIR)/cdx-$(PKG_VERSION)

# Keep Stage 2 on the wired first-class only. WiFi and IPsec stay on their
# later milestones and are compiled in only when their flags are re-enabled.
CDX_MAKE_OPTS:= \
	PLATFORM=LS1043A \
	KERNELDIR="$(LINUX_DIR)" \
	KERNEL_SRC="$(LINUX_DIR)" \
	CFG_FLAGS="-DSEC_PROFILE_SUPPORT -DVLAN_FILTER -DENABLE_EGRESS_QOS -DCONFIG_FSL_DPAA_ETH_REFILL_THRESHOLD=80"

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
