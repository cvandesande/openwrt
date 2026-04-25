#
# Copyright (C) 2025 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=leds-lp5812
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define KernelPackage/leds-lp5812
  SUBMENU:=LED modules
  TITLE:=Texas Instruments LP5812 LED Matrix Driver
  FILES:=$(PKG_BUILD_DIR)/leds-lp5812.ko
  AUTOLOAD:=$(call AutoProbe,leds-lp5812,1)
  DEPENDS:=+kmod-i2c-core
endef

define KernelPackage/leds-lp5812/description
  Linux kernel driver for Texas Instruments LP5812 LED controller.
  Supports 4x3 LED matrix via I2C with multicolor LED support.
endef

define Build/Compile
	$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,leds-lp5812))
