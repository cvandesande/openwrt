#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=maya-w2-wifi-diag
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/maya-w2-wifi-diag
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=MAYA-W2 Wi-Fi diagnostics collector
  DEPENDS:=+kmod-nxp-mxm-wifi
  PKGARCH:=all
endef

define Package/maya-w2-wifi-diag/description
  Collects non-invasive diagnostics for first hardware validation of the
  u-blox MAYA-W2 Wi-Fi card on Mono Gateway DK.
endef

define Build/Compile
endef

define Package/maya-w2-wifi-diag/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/maya-w2-wifi-diag $(1)/usr/bin/
endef

$(eval $(call BuildPackage,maya-w2-wifi-diag))
