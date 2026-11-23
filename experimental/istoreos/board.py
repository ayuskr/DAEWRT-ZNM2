"""Apply the ZN M2 NAND board profile to the pinned iStoreOS source tree."""
from pathlib import Path

board = Path('target/linux/qualcommax')
donor = Path('../donor') / board
dts = Path('files/arch/arm64/boot/dts/qcom')
# Keep the donor's ZN M2 PHY and port map on iStoreOS's native ethernet stack.
common = (donor / dts / 'ipq6000-cmiot.dtsi').read_text()
common = common.replace('#include "ipq6018-nss.dtsi"', '').replace('#include "ipq6018-common.dtsi"', '#include "ipq6018-cp-cpu.dtsi"')
# UART, MDIO mux and NAND BAM use the native IPQ6000 pinctrl/clock bindings.
reference = (board / dts / 'ipq6000-360v6.dts').read_text()
common += '\n' + reference[reference.index('&tlmm {'):reference.index('&qpic_nand {')]
(board / dts / 'ipq6000-cmiot.dtsi').write_text(common)
model = (donor / dts / 'ipq6000-m2.dts').read_text()
(board / dts / 'ipq6000-m2.dts').write_text(model[:model.index('&wifi {')] + '&wifi { status = "disabled"; };\n')
recipe = (donor / 'image/ipq60xx.mk').read_text()
profile = recipe[recipe.index('define Device/zn_m2\n'):recipe.index('TARGET_DEVICES += zn_m2') + len('TARGET_DEVICES += zn_m2')]
profile = profile.replace('ipq-wifi-zn_m2', '-kmod-ath11k-ahb -ath11k-firmware-ipq6018 -wpad-basic-mbedtls')
with (board / 'image/ipq60xx.mk').open('a') as target:
    target.write('\n' + profile + '\n')
for path in ['etc/board.d/02_network', 'lib/upgrade/platform.sh']:
    target = board / 'ipq60xx/base-files' / path
    text = target.read_text()
    # First case in 02_network only: do not inherit the 360V6 MAC extraction.
    anchor = 'qihoo,360v6)'
    assert anchor in text, path
    target.write_text(text.replace(anchor, 'zn,m2|' + anchor, 1))
