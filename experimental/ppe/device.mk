
define Device/zn_m2
	$(call Device/FitImage)
	DEVICE_VENDOR := ZN
	DEVICE_MODEL := M2
	SOC := ipq6000
	DEVICE_DTS_CONFIG := config@cp03-c1
	IMAGES :=
endef
TARGET_DEVICES += zn_m2
