include $(TOPDIR)/rules.mk

PKG_NAME:=psutil-release
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
PKG_LICENSE:=BSD
PKG_LICENSE_FILES:=PKG-INFO

PKG_SOURCE:=$(PKG_NAME)$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/giampaolo/psutil/archive/release-$(PKG_VERSION).tar.gz


include $(INCLUDE_DIR)/package.mk
include ../../lang/python/files/python-package.mk

define Package/python-psutil
  SUBMENU:=Python
  SECTION:=lang
  CATEGORY:=Languages
  TITLE:=python-psutil
  DEPENDS:=+python
endef

define Package/python-psutil/description
  psutil is a module providing an interface for retrieving information on all running processes and system utilization (CPU, memory, disks, network, users) in a portable way by using Python.
endef

define Build/Compile
	$(call Build/Compile/PyMod,., \
		install --prefix="/usr" --root="$(PKG_INSTALL_DIR)" \
	)
endef

define Package/python-psutil/install
	$(INSTALL_DIR) $(1)$(PYTHON_PKG_DIR)
	$(CP) \
		$(PKG_INSTALL_DIR)$(PYTHON_PKG_DIR)/* \
		$(1)$(PYTHON_PKG_DIR)/
endef

$(eval $(call BuildPackage,python-psutil))
