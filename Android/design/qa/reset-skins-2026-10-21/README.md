# Reset information layout verification

Device: Samsung SM-G986N, actual USB-connected phone. Landscape captures are 2400 × 1080; portrait captures are 1080 × 2400.

The six captures render the production CodexStatusPage through the debug-only SkinVerificationActivity. They use sample values (43% / 76%, almost five hours / almost seven days) rather than live account usage. The fixture does not render the main app header, so a final live MainActivity capture is separate.

- Orbital Pixel: mint/violet usage panels contain the gauge and reset footer together, with an opaque background for legibility over the space artwork.
- Dot Matrix: cyan/violet usage panels contain their own reset footer; the duplicated detached right-side gauges are removed.
- Pixel Quest: the card footer separates the gauge from the reset information; reset time starts at the left edge and countdown ends at the right edge. Countdown color follows the coral/gold card accent.
- Both orientations: the UI hierarchy contains all four reset fields with non-empty bounds entirely inside the screenshot. Dates and countdowns can wrap when necessary.

The screenshot names contain the skin ID and verified orientation. Matching XML files preserve actual device UI bounds.

Final release APK installed successfully on the same phone. `live-final.png` and `live-final.xml` show MainActivity connected to the Mac and Codex with live Dot Matrix usage and reset data. Unit tests: 66 passed, zero failures/errors. Debug and release builds succeeded. Original rotation settings were restored (accelerometer_rotation=1, user_rotation=0).
