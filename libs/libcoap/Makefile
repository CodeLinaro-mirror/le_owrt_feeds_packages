
include $(TOPDIR)/rules.mk

PKG_NAME:=libcoap
PKG_VERSION:=v4.2.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/obgm/libcoap
PKG_SOURCE_VERSION:=$(PKG_VERSION)

PKG_SOURCE:=$(PKG_NAME)-$(PKG_SOURCE_VERSION).tar.gz

PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_SOURCE_VERSION)

PKG_LICENSE:=BSD-2-Clause

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_SOURCE_VERSION)

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/libcoap
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=CoAP (RFC 7252) library
endef

define Package/libcoap/description
  Constrained Application Protocol (RFC 7252) library
endef

TARGET_CFLAGS += $(FPIC)

CONFIGURE_ARGS += \
	--enable-examples \
	--disable-dtls\
	--disable-documentation

ifeq ($(CONFIG_BIG_ENDIAN),y)
TARGET_CFLAGS += -DWORDS_BIGENDIAN
endif

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/* $(1)/usr/include/

	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/* $(1)/usr/lib/
endef

define Package/libcoap/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libcoap-2.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libcoap))
