#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=fmc
PKG_VERSION:=6.12.49
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/nxp-qoriq/fmc.git
PKG_SOURCE_VERSION:=5b9f4b16a864e9dfa58cdcc860be278a7f66ac18
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=tclap

include $(INCLUDE_DIR)/package.mk

define Package/fmc
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=NXP Frame Manager Configuration tool
  DEPENDS:=@TARGET_layerscape +libxml2 +fmlib +libstdcpp
  URL:=https://github.com/nxp-qoriq/fmc
endef

define Package/fmc/description
  FMC (Frame Manager Configuration) is a command-line tool that parses
  and applies FMan hardware configurations from XML policy files.
endef

# Convert CRLF to LF before patching (upstream has Windows line endings)
define Build/Prepare
	$(PKG_UNPACK)
	find $(PKG_BUILD_DIR)/source -type f \( -name "*.cpp" -o -name "*.h" -o -name "*.c" \) -exec perl -pi -e 's/\r\n/\n/g' {} +
	$(Build/Patch)
endef

MAKE_FLAGS += \
	FMD_USPACE_HEADER_PATH="$(STAGING_DIR)/usr/include/fmd" \
	FMD_USPACE_LIB_PATH="$(STAGING_DIR)/usr/lib" \
	LIBXML2_HEADER_PATH="$(STAGING_DIR)/usr/include/libxml2" \
	TCLAP_HEADER_PATH="$(STAGING_DIR)/usr/include" \
	MACHINE=ls1046

# Disable parallel make - fmc has build dependency issues
PKG_BUILD_PARALLEL:=0

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/source \
		$(MAKE_FLAGS) \
		CC="$(TARGET_CC)" \
		CXX="$(TARGET_CXX)"
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/fmc
	$(CP) $(PKG_BUILD_DIR)/source/fmc.h $(1)/usr/include/fmc/

	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/source/libfmc.a $(1)/usr/lib/
endef

define Package/fmc/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/source/fmc $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/etc/fmc/config
	if [ -d $(PKG_BUILD_DIR)/etc/fmc/config ]; then \
		$(CP) $(PKG_BUILD_DIR)/etc/fmc/config/* $(1)/etc/fmc/config/; \
	fi
endef

$(eval $(call BuildPackage,fmc))
