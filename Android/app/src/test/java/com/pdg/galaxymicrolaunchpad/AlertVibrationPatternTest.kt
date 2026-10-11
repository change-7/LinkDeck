package com.pdg.galaxymicrolaunchpad

import org.junit.Assert.*
import org.junit.Test

class AlertVibrationPatternTest {
    @Test fun patternsAreDistinctAndFinite() {
        val active = AlertVibrationPattern.entries.filter { it != AlertVibrationPattern.OFF }
        assertEquals(active.size, active.map { it.timings.toList() }.distinct().size)
        active.forEach {
            assertEquals(0L, it.timings.first())
            assertTrue(it.timings.drop(1).all { duration -> duration > 0 })
            assertTrue(it.timings.sum() < 3000)
        }
        assertTrue(AlertVibrationPattern.OFF.timings.isEmpty())
    }
}
