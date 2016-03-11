# Copyright (C) 2006-2012 OpenWrt.org
# Copyright (C) 2015 The Linux Foundation. All rights reserved.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=bluez
PKG_VERSION:=5.37
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=http://www.kernel.org/pub/linux/bluetooth
PKG_MD5SUM:=33177e5743e24b2b3738f72be64e3ffb

PKG_FIXUP:=autoreconf

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/nls.mk

define Package/bluez
  SECTION:=utils
  CATEGORY:=Utilities
  DEPENDS:=+libpthread +libusb-compat +glib2 +dbus +udev \
	  $(INTL_DEPENDS) $(ICONV_DEPENDS) +libreadline +libtinfo
  TITLE:=Bluez combined libs & utils (v5.*)
  URL:=http://www.bluez.org/
endef

define Package/bluez/conffiles
/etc/config/bluetooth
endef

CONFIGURE_ARGS += \
	--enable-library \
	--disable-systemd \
	--disable-monitor \
	--disable-cups \
	--enable-client \
	--disable-obex \
	--enable-usb \
	--disable-audio \
	--with-usb=yes \
	--with-udevdir="$(STAGING_DIR)/lib/udev"

CONFIGURE_VARS+= \
	LDFLAGS="$$$$LDFLAGS -L$(ICONV_PREFIX)/lib" \
	LDFLAGS="$$$$LDFLAGS -L$(INTL_PREFIX)/lib -lm -ltinfo"

define Package/bluez/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/dbus-1/system.d
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/bluetooth
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/bccmd $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/hciattach $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/hcidump $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/l2ping $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/rctest  $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/sdptool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/ciptool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/hciconfig $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/hcitool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/l2test $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/rfcomm $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/client/bluetoothctl $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/bluetoothd $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/attrib/gatttool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/hid2hci $(1)/usr/bin/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/bluetooth.conf $(1)/etc/dbus-1/system.d/bluetooth.conf
	$(INSTALL_BIN) ./files/bluetooth.init $(1)/etc/init.d/bluetooth
	$(INSTALL_BIN) ./files/bluez-bccmd.init $(1)/etc/init.d/bluez-bccmd
	$(INSTALL_DATA) ./files/csr8x11-a12-bt4.2-patch.psr $(1)/etc/bluetooth/
	$(INSTALL_DATA) ./files/csr8x11-coex.psr $(1)/etc/bluetooth/
endef

$(eval $(call BuildPackage,bluez))
