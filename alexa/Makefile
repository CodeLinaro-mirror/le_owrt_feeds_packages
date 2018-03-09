include $(TOPDIR)/rules.mk

PKG_NAME:=avs-device-sdk
PKG_VERSION:=1.6
PKG_RELEASE:=0
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).$(PKG_RELEASE).tar.bz2
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION).$(PKG_RELEASE)
PKG_SOURCE_URL:=https://github.com/alexa/avs-device-sdk.git
PKG_SOURCE_BRANCH:=github/master
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=46fd5482bcc481e2fb7445d434d21ab7e5685529
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)
CMAKE_INSTALL:=1

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/avs-device-sdk
  SECTION:=ALEXA
  CATEGORY:=ALEXA software
  TITLE:=Alexa
  URL:=
  DEPENDS:=+libcurl +glib2 +gst1-plugins-base +libgstreamer1 +libstdcpp +libsqlite3 +alsa-plugins-gcs +graphite-client +wdsp-fw
endef

TARGET_LDFLAGS += -lcurl -lsqlite3

CMAKE_OPTIONS += \
	-DACSDK_EXCLUDE_TEST_FROM_ALL=ON \
	-DSENSORY_KEY_WORD_DETECTOR=OFF \
	-DGSTREAMER_MEDIA_PLAYER=ON \
	-DCURL_LIBRARY=${STAGING_DIR}/usr/lib/ \
	-DCURL_INCLUDE_DIR=${STAGING_DIR}/usr/include/

define Package/avs-device-sdk/description
 Alexa voice assistance for AVS.
endef

define Package/avs-device-sdk/install
	$(INSTALL_DIR) $(1)/alexa $(1)/usr/lib $(1)/usr/bin $(1)/etc/ssl $(1)/etc/ssl/certs $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ACL/src/libACL.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ADSL/src/libADSL.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/AFML/src/libAFML.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ApplicationUtilities/DefaultClient/src/libDefaultClient.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ApplicationUtilities/Resources/Audio/src/libAudioResources.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/AuthDelegate/src/libAuthDelegate.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/AVSCommon/libAVSCommon.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/AIP/src/libAIP.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/Alerts/src/libAlerts.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/AudioPlayer/src/libAudioPlayer.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/ExternalMediaPlayer/src/libExternalMediaPlayer.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/Notifications/src/libNotifications.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/PlaybackController/src/libPlaybackController.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/Settings/src/libSettings.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/SpeakerManager/src/libSpeakerManager.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/SpeechSynthesizer/src/libSpeechSynthesizer.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/System/src/libAVSSystem.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CapabilityAgents/TemplateRuntime/src/libTemplateRuntime.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CertifiedSender/src/libCertifiedSender.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ContextManager/src/libContextManager.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/MediaPlayer/src/libMediaPlayer.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/PlaylistParser/src/libPlaylistParser.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/RegistrationManager/src/libRegistrationManager.so $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/Storage/SQLiteStorage/src/libSQLiteStorage.so $(1)/usr/lib
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
