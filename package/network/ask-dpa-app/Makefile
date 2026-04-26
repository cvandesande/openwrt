#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ask-dpa-app
PKG_VERSION:=4.03.0
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/we-are-mono/ASK.git
# When PKG_SOURCE_VERSION changes, run this and update PKG_MIRROR_HASH:
#   scripts/mono-check-vendor-hashes.sh package/network/ask-dpa-app
PKG_SOURCE_VERSION:=beefead3fc638a79e16c237c99182628f8b96cc9
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_MIRROR_HASH:=c4b183d5ff6ca4330147cc3438ca9daaf2fa780e33588c213ab5ecc330ac166c
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING.GPL

include $(INCLUDE_DIR)/package.mk

define Package/ask-dpa-app
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=NXP ASK DPA configuration utility
  DEPENDS:=@TARGET_layerscape +libcli +fmc +fmlib +libxml2 +kmod-ask-cdx
  URL:=https://github.com/we-are-mono/ASK
endef

define Package/ask-dpa-app/description
  Data Path Acceleration (DPA) application for configuring fast path
  offload on NXP Layerscape processors. Called by the CDX kernel module
  at boot time to load configuration. Part of the Application Solutions
  Kit (ASK).
endef

# The source is in dpa_app-X.XX.X subdirectory
define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) $(PKG_BUILD_DIR)/dpa_app-$(PKG_VERSION)/* $(PKG_BUILD_DIR)/
endef

# Build flags per NXP ASK documentation - must match CDX flags
TARGET_CFLAGS += \
	-DENDIAN_LITTLE \
	-DLS1043 \
	-DNCSW_LINUX \
	-DDPAA_DEBUG_ENABLE \
	-DSEC_PROFILE_SUPPORT \
	-DVLAN_FILTER \
	-I$(STAGING_DIR)/usr/include/fmc \
	-I$(STAGING_DIR)/usr/include/fmd \
	-I$(STAGING_DIR)/usr/include/fmd/integrations \
	-I$(STAGING_DIR)/usr/include/fmd/Peripherals \
	-I$(STAGING_DIR)/usr/include/fmd/Peripherals/common \
	-I$(STAGING_DIR)/usr/include/cdx

TARGET_LDFLAGS += -lfmc -lfm-arm -lstdc++ -lxml2 -lpthread -lcli

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define Package/ask-dpa-app/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/dpa_app $(1)/usr/bin/
	$(INSTALL_BIN) ./files/dpa_app_wrapper $(1)/usr/bin/

	# Keep bootstrap XML out of /etc so flashed images always use the
	# package-owned exact-scope board config rather than preserved overlay state.
	$(INSTALL_DIR) $(1)/usr/share/ask-dpa-app
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/etc/*.xml $(1)/usr/share/ask-dpa-app/
	$(INSTALL_DATA) ./files/cdx_cfg.xml $(1)/usr/share/ask-dpa-app/
endef

$(eval $(call BuildPackage,ask-dpa-app))
