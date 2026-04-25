#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libfci
PKG_VERSION:=9.00.12
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/cvandesande/fci.git
PKG_SOURCE_VERSION:=655983ec1e5bbc7c2892ac5c35fb431b97d05c00
PKG_SOURCE_SUBDIR:=fci-source-$(PKG_VERSION)
PKG_MIRROR_HASH:=65ebd6f2a97186e602fc47a50e40eb4f33f234f21273eabc877a6377b06d36f4
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
