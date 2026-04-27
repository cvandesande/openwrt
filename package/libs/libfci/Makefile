#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libfci
PKG_VERSION:=9.00.12
PKG_RELEASE:=3

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/cvandesande/fci.git
# When PKG_SOURCE_VERSION changes, run this and update PKG_MIRROR_HASH:
#   scripts/mono-check-vendor-hashes.sh package/kernel/ask-fci package/libs/libfci
PKG_SOURCE_VERSION:=5b8cfa8453969f0538fe90870f750e22aea80cbb
PKG_SOURCE_SUBDIR:=fci-source-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.zst
PKG_MIRROR_HASH:=99b5692ec40ba14d8fda45996d25129070d13365520b8f86d464d9f5d518e85b
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING.GPL

PKG_BUILD_PARALLEL:=1
PKG_FIXUP:=autoreconf
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/libfci
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=NXP ASK FCI userspace library
  DEPENDS:=@TARGET_layerscape
  URL:=https://github.com/cvandesande/fci
endef

define Package/libfci/description
  Userspace library for communicating with the FCI kernel module.
  Part of the NXP Application Solutions Kit (ASK).
endef

CONFIGURE_PATH:=fci-$(PKG_VERSION)/lib
MAKE_PATH:=fci-$(PKG_VERSION)/lib

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_BUILD_DIR)/fci-$(PKG_VERSION)/lib/include/libfci.h $(1)/usr/include/

	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libfci.{so*,a,la} $(1)/usr/lib/
endef

define Package/libfci/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libfci.so.* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libfci))
