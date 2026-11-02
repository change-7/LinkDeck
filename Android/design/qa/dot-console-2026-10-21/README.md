# Dot Console verification

Final captures `live-portrait.png` and `live-landscape.png` show the actual MainActivity on the connected Samsung SM-G986N with live Mac usage and reset-credit data. The earlier `portrait.png` and `landscape.png` are isolated debug fixtures and do not represent the full portrait app.

Portrait preserves the existing action grid and places compact weekly, five-hour and reset-credit panels underneath. There is no separate status-motion panel. Reset credits use the same panel frame, a dot icon, available count, expiration dates and remaining durations.

Landscape places the two usage panels side by side above reset credits. Final UI hierarchy: no scrollable regions with the two available credits. The status dots animate while running; consecutive device frames were compared in the status-dot rectangle and differed. `motion-second-frame.png` retains the second frame.

Android unit tests: 66 passed. Release build passed and was installed. Mac theme tests: 3 passed, covering deletion persistence, selected-skin fallback, inactive deletion, classic protection, restoration and wire encoding. Native settings click automation remained unavailable because its control process disconnected when opening settings; no visual settings verification is claimed.

Mac and phone use the `dotConsole` identifier. Settings offer deletion for non-classic skins; deleting the selected skin falls back to classic, and deleted skins can be restored. The original phone rotation mode was restored after capture.

The header and main status panel now share DotConsoleStatusMotion. `header-portrait-a/b.png` and `header-landscape-a/b.png` are consecutive live device frames. Bright-dot masks changed inside the header icon rectangle in both orientations, confirming moving dots rather than only changing text opacity. The final Android release was installed and the Mac app was updated with the skin authoring requirements disclosure and copy button under Phone Skins.
