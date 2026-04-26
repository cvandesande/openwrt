#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=fmlib
PKG_VERSION:=6.12.49
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/nxp-qoriq/fmlib.git
PKG_SOURCE_VERSION:=7a58ecaf0d90d71d6b78d3ac7998282a472c4394
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_MIRROR_HASH:=1c83d95d0d8bf844f7082b02d1ef3ed2970075ec88f0a2825d6aab9ae9c6d05c
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=BSD-3-Clause GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/fmlib
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=NXP Frame Manager library
  DEPENDS:=@TARGET_layerscape
  URL:=https://github.com/nxp-qoriq/fmlib
endef

define Package/fmlib/description
  Frame Manager User Space Library for NXP Layerscape processors.
  Provides the interface for configuring the Frame Manager hardware.
endef

MAKE_FLAGS += \
	DESTDIR="$(PKG_INSTALL_DIR)" \
	PREFIX=/usr \
	LIB_DEST_DIR=/usr/lib \
	KERNEL_SRC="$(LINUX_DIR)"

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		$(MAKE_FLAGS) \
		libfm-arm.a
endef

define Build/Install
	$(MAKE) -C $(PKG_BUILD_DIR) \
		$(MAKE_FLAGS) \
		install-libfm-arm
	rm -rf $(PKG_INSTALL_DIR)/usr/src
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/fmd
	$(CP) $(PKG_INSTALL_DIR)/usr/include/fmd/* $(1)/usr/include/fmd/

	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libfm-arm.a $(1)/usr/lib/
	ln -sf libfm-arm.a $(1)/usr/lib/libfm.a
endef

define Package/fmlib/install
	true
endef

$(eval $(call BuildPackage,fmlib))
