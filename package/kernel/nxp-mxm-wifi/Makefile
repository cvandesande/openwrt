#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=nxp-mxm-wifi
PKG_VERSION:=6.12.49.2.2.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/nxp-imx/mwifiex.git
PKG_SOURCE_DATE:=2025-11-14
PKG_SOURCE_VERSION:=84ca65c9ff935d7f2999af100a82531c22c65234
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-lf-6.12.49-2.2.0
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.zst
PKG_MIRROR_HASH:=30c275897810a209d9f95e8c543a2f9eea7a0863fb665c54b109642876d6d913

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_PARALLEL:=1
PKG_FLAGS:=nonshared

STAMP_CONFIGURED_DEPENDS := $(STAGING_DIR)/usr/include/mac80211-backport/backport/autoconf.h

include $(INCLUDE_DIR)/kernel.mk

PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

include $(INCLUDE_DIR)/package.mk

define KernelPackage/nxp-mxm-wifi
  SUBMENU:=Wireless Drivers
  TITLE:=NXP MXM Wi-Fi driver for IW612 SDIO
  URL:=https://github.com/nxp-imx/mwifiex
  DEPENDS:=@TARGET_layerscape @LINUX_6_12 +kmod-cfg80211 +kmod-mmc +nxp-maya-w2-firmware
  FILES:= \
	$(PKG_BUILD_DIR)/mlan.ko \
	$(PKG_BUILD_DIR)/moal.ko
  AUTOLOAD:=$(call AutoLoad,50,mlan moal)
  MODPARAMS.moal:=mod_para=nxp/wifi_mod_para.conf
endef

define KernelPackage/nxp-mxm-wifi/description
  Optional NXP out-of-tree MXM Wi-Fi driver package for the u-blox
  M2-MAYA-W271 / MAYA-W2 card on Mono Gateway DK. This package builds only the
  SDIO IW612 path and does not replace OpenWrt's upstream mwifiex packages.
endef

NXP_MXM_WIFI_MAKE_FLAGS:= \
	ARCH="$(LINUX_KARCH)" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	KERNELDIR="$(LINUX_DIR)" \
	CONFIG_OPENWRT_SUPPORT=y \
	CONFIG_CFG80211=m \
	CPTCFG_CFG80211=m \
	CONFIG_SD8887=n \
	CONFIG_SD8897=n \
	CONFIG_USB8897=n \
	CONFIG_PCIE8897=n \
	CONFIG_SD8977=n \
	CONFIG_SD8978=n \
	CONFIG_USB8978=n \
	CONFIG_SD8997=n \
	CONFIG_USB8997=n \
	CONFIG_PCIE8997=n \
	CONFIG_SD8987=n \
	CONFIG_SD9097=n \
	CONFIG_SD9177=y \
	CONFIG_SD8801=n \
	CONFIG_USB8801=n \
	CONFIG_USB9097=n \
	CONFIG_PCIE9097=n \
	CONFIG_SD9098=n \
	CONFIG_USB9098=n \
	CONFIG_PCIE9098=n \
	CONFIG_SDIW610=n \
	CONFIG_USBIW610=n \
	CONFIG_SDIW624=n \
	CONFIG_SDAW693=n \
	CONFIG_PCIEIW624=n \
	CONFIG_USBIW624=n \
	CONFIG_PCIEAW693=n \
	CONFIG_WIFI_DIRECT_SUPPORT=n \
	CONFIG_MFG_CMD_SUPPORT=n

NOSTDINC_FLAGS := \
	$(KERNEL_NOSTDINC_FLAGS) \
	-I$(PKG_BUILD_DIR)/mlan \
	-I$(PKG_BUILD_DIR)/mlinux \
	-I$(STAGING_DIR)/usr/include/mac80211-backport/uapi \
	-I$(STAGING_DIR)/usr/include/mac80211-backport \
	-I$(STAGING_DIR)/usr/include/mac80211/uapi \
	-I$(STAGING_DIR)/usr/include/mac80211 \
	-include backport/backport.h \
	-DNXP_MXM_OPENWRT_NEW_CFG80211_OPS \
	-Wno-error=implicit-fallthrough \
	-Wno-error=unused-function

define Build/Compile
	+$(KERNEL_MAKE) $(PKG_JOBS) \
		M="$(PKG_BUILD_DIR)" \
		NOSTDINC_FLAGS="$(NOSTDINC_FLAGS)" \
		$(NXP_MXM_WIFI_MAKE_FLAGS) \
		modules
endef

$(eval $(call KernelPackage,nxp-mxm-wifi))
