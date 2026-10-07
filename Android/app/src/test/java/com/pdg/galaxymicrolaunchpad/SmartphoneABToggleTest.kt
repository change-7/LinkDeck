package com.pdg.galaxymicrolaunchpad

import org.junit.Assert.assertEquals
import org.junit.Test

class SmartphoneABToggleTest {
    @Test
    fun testActiveToggleStateSelectsActionB() {
        assertEquals("url", resolveSmartphoneShortPressAction("shortcut", "url", true))
    }

    @Test
    fun testInactiveToggleStateSelectsActionA() {
        assertEquals("shortcut", resolveSmartphoneShortPressAction("shortcut", "url", false))
    }

    @Test
    fun testLegacyButtonWithoutBUsesActionA() {
        assertEquals("shortcut", resolveSmartphoneShortPressAction("shortcut", null, false))
    }
}
