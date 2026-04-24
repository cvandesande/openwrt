#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libcli
PKG_VERSION:=1.10.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/dparrish/libcli.git
PKG_SOURCE_VERSION:=6a3b2f96c4f0916e2603a96bf24d704f6a904e7a
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_MIRROR_HASH:=abb95ae853ba74ab6d54280be143549ff6a93aca398490db256cb77f67ebaba2
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=LGPL-2.1-only
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/libcli
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Cisco-like CLI library
  URL:=https://github.com/dparrish/libcli
endef

define Package/libcli/description
  libcli provides a shared library for including a Cisco-like command-line
  interface into other software. It supports telnet or local connections,
  handles command history, and provides tab completion.
endef

MAKE_FLAGS += \
	PREFIX=/usr \
	CFLAGS="$(TARGET_CFLAGS) -Wno-calloc-transposed-args"

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_BUILD_DIR)/libcli.h $(1)/usr/include/

	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/libcli.so* $(1)/usr/lib/
endef

define Package/libcli/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/libcli.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libcli))
