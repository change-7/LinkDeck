package com.pdg.galaxymicrolaunchpad

import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class ButtonGridFitTest {
    @Test
    fun allRowsFitShortTallAndFractionalDensityScreens() {
        for (height in listOf(240, 351, 480, 701, 1200)) {
            for (gap in listOf(10, 26, 30)) {
                for (rows in listOf(4, 5, 8)) {
                    val tile = fittedButtonHeightPx(height, gap, rows)
                    val used = tile * rows + gap * (rows - 1)
                    assertTrue("height=$height gap=$gap rows=$rows", used <= height)
                    assertTrue(height - used < rows)
                }
            }
        }
    }

    @Test
    fun emptyPageDoesNotDivideByZero() {
        assertEquals(0, fittedButtonHeightPx(400, 10, 0))
    }
}
