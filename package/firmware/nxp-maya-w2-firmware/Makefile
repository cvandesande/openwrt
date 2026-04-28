#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=nxp-maya-w2-firmware
PKG_VERSION:=6.12.49.2.2.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/nxp-imx/imx-firmware.git
PKG_SOURCE_DATE:=2025-11-14
PKG_SOURCE_VERSION:=8c9b278016c97527b285f2fcbe53c2d428eb171d
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-lf-6.12.49-2.2.0
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.zst
PKG_MIRROR_HASH:=99bd321d94444c9ef345c29c61581294a8ce4fb2cf8b80f2377b8f43da37fd6f
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=NXP-Proprietary
PKG_LICENSE_FILES:=LICENSE.txt SCR-imx-firmware.txt
PKG_FLAGS:=nonshared

include $(INCLUDE_DIR)/package.mk

define Package/nxp-maya-w2-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=NXP IW612 SDIO firmware for u-blox MAYA-W2
  URL:=https://github.com/nxp-imx/imx-firmware
  PKGARCH:=all
endef

define Package/nxp-maya-w2-firmware/description
  Optional proprietary NXP IW612 SDIO firmware files for the u-blox
  M2-MAYA-W271 / MAYA-W2 card. Firmware is fetched from NXP during the
  OpenWrt build and is not stored in this repository.
endef

define Build/Compile
endef

define Package/nxp-maya-w2-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/nxp
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/FwImage_IW612_SD/sd_w61x_v1.bin.se \
		$(PKG_BUILD_DIR)/FwImage_IW612_SD/sduart_nw61x_v1.bin.se \
		$(PKG_BUILD_DIR)/FwImage_IW612_SD/uartspi_n61x_v1.bin.se \
		$(PKG_BUILD_DIR)/FwImage_IW612_SD/uartuart_n61x_v1.bin.se \
		$(PKG_BUILD_DIR)/wifi_mod_para.conf \
		$(1)/lib/firmware/nxp/
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/LICENSE.txt \
		$(1)/lib/firmware/nxp/LICENSE.IW612-NXP.txt
endef

$(eval $(call BuildPackage,nxp-maya-w2-firmware))
