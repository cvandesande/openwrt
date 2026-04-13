# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 Mono Technologies Inc.

include $(TOPDIR)/rules.mk

PKG_NAME:=fancontrol
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/fancontrol
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Fan control daemon for EMC2305
  URL:=https://openwrt.org/
  DEPENDS:=+kmod-hwmon-core +kmod-hwmon-emc2305 +kmod-hwmon-tmp421
  MAINTAINER:=Mono Technologies Inc.
endef

define Package/fancontrol/description
  Userspace fan control daemon for Microchip EMC2305 fan controller.
  Reads temperature sensors and adjusts fan speed linearly.
endef

define Package/fancontrol/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/fancontrol-emc2305 $(1)/usr/sbin/
	
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/fancontrol.init $(1)/etc/init.d/
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/fancontrol.config $(1)/etc/config/
endef

$(eval $(call BuildPackage,fancontrol))
