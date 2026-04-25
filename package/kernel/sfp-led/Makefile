#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=sfp-led
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define KernelPackage/sfp-led
  SUBMENU:=LED modules
  TITLE:=SFP LED Control Platform Driver
  FILES:=$(PKG_BUILD_DIR)/sfp-led.ko
  AUTOLOAD:=$(call AutoProbe,sfp-led,1)
  DEPENDS:=@TARGET_layerscape
endef

define KernelPackage/sfp-led/description
  Controls SFP port LEDs based on module presence and optical signal state.
  Registers with the SFP bus to receive hotplug and link state events.
endef

define Build/Compile
	$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,sfp-led))
