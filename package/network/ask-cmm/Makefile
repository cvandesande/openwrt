#
# Copyright (C) 2026 Mono Technologies Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ask-cmm
PKG_VERSION:=17.03.1
PKG_RELEASE:=5

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/cvandesande/ask-cmm.git
# When PKG_SOURCE_VERSION changes, run this and update PKG_MIRROR_HASH:
#   scripts/mono-check-vendor-hashes.sh package/network/ask-cmm
PKG_SOURCE_VERSION:=6698c2a14cde768163bdfc7f8463f9c3ec15b691
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_MIRROR_HASH:=19595b5ac5f31816c597628d65d3fb36fb248b5929f58efbae55a4c508bfb140
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING.GPL

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=0

include $(INCLUDE_DIR)/package.mk

define Package/ask-cmm
  SECTION:=net
  CATEGORY:=Network
  TITLE:=NXP ASK Connection Manager daemon
  DEPENDS:=@TARGET_layerscape +libnetfilter-conntrack +libfci +libcli +libpcap \
	+kmod-nf-conntrack +kmod-nf-conntrack-netlink +kmod-nf-nat \
	+kmod-br-netfilter
  URL:=https://github.com/cvandesande/ask-cmm
endef

define Package/ask-cmm/description
  Connection Manager Module (CMM) daemon for managing fast path network
  offloading on NXP Layerscape processors. Part of the Application
  Solutions Kit (ASK).
endef

# Build only the wired-first Stage 2 surface. WiFi, auto-bridge, the KEY/IPsec
# FCI channel, QoS connmark, and the vendor XFRM-handle conntrack ABI stay
# deferred until their milestone.
TARGET_CFLAGS += \
	-Wno-error \
	-DASK_STAGE2_SKIP_XFRM_CONNTRACK_ABI \
	-DLS1043 \
	-DFLOW_STATS \
	-DIPSEC_SUPPORT_DISABLED \
	-DIPSEC_NO_FLOW_CACHE \
	-DSEC_PROFILE_SUPPORT \
	-DENABLE_EGRESS_QOS \
	-DENABLE_INGRESS_QOS \
	-DVLAN_FILTER

define Package/ask-cmm/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/cmm $(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libcmm.so* $(1)/usr/lib/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/fastforward $(1)/etc/config/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/cmm.init $(1)/etc/init.d/cmm
endef

$(eval $(call BuildPackage,ask-cmm))
