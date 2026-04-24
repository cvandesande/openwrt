include $(TOPDIR)/rules.mk

PKG_NAME:=tclap
PKG_VERSION:=1.2.5
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=@SF/tclap
PKG_HASH:=bb649f76dae35e8d0dcba4b52acfd4e062d787e6a81b43f7a4b01275153165a6

PKG_MAINTAINER:=Tomaz Zaman <tomaz@mono.si>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/tclap
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Templatized C++ Command Line Parser Library
  URL:=http://tclap.sourceforge.net/
  BUILDONLY:=1
endef

define Package/tclap/description
  TCLAP is a small, flexible library that provides a simple interface
  for defining and accessing command line arguments. It is header-only,
  so no build is required.
endef

define Build/Configure
endef

define Build/Compile
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_BUILD_DIR)/include/tclap $(1)/usr/include/
endef

$(eval $(call BuildPackage,tclap))
