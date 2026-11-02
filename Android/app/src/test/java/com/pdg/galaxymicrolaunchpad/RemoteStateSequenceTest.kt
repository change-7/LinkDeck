package com.pdg.galaxymicrolaunchpad

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteStateSequenceTest {
    @Test fun rejectsDuplicatesOutOfOrderAndPreviousMacSessions() {
        val gate = RemoteStateSequence()
        val resources = mapOf("buttons" to "new")
        assertTrue(gate.synchronize("mac", 4, resources))
        assertFalse(gate.acceptState("mac", 4, emptyMap()))
        assertTrue(gate.acceptState("mac", 4, resources))
        assertFalse(gate.acceptState("mac", 4, resources))
        assertFalse(gate.acceptState("mac", 3, resources))
        assertFalse(gate.synchronize("mac", 3, mapOf("buttons" to "old")))
        assertFalse(gate.synchronize("other-mac", 100, resources))
        assertFalse(gate.acceptState("other-mac", 100, resources))
        assertTrue(gate.synchronize("mac", 5, resources))
        assertTrue(gate.acceptState("mac", 5, resources))
    }

    @Test fun reconnectRequiresAuthoritativeSnapshotAndAllChangedResources() {
        val gate = RemoteStateSequence()
        val old = mapOf("buttons" to "old", "icons" to "old")
        assertTrue(gate.synchronize("mac", 8, old))
        assertTrue(gate.acceptState("mac", 8, old))
        gate.resetConnection()
        assertFalse(gate.acceptState("mac", 9, old))
        val latest = mapOf("buttons" to "new", "icons" to "new")
        assertTrue(gate.synchronize("mac", 9, latest))
        assertFalse(gate.acceptState("mac", 9, old))
        assertFalse(gate.acceptState("mac", 9, mapOf("buttons" to "new", "icons" to "old")))
        assertTrue(gate.acceptState("mac", 9, latest))
        gate.resetConnection()
        assertTrue(gate.synchronize("restarted-mac", 1, latest))
        assertTrue(gate.acceptState("restarted-mac", 1, latest))
    }
}
