package com.pdg.galaxymicrolaunchpad

internal class RemoteStateSequence {
    var sessionID: String? = null
        private set
    var expectedResources: Map<String, String> = emptyMap()
        private set
    private var synchronizedSequence = -1L
    private var appliedSequence = -1L

    fun resetConnection() {
        sessionID = null
        synchronizedSequence = -1
        appliedSequence = -1
        expectedResources = emptyMap()
    }

    fun synchronize(session: String, sequence: Long, resources: Map<String, String>): Boolean {
        if (session.isBlank() || sequence < 0 || sessionID != null && sessionID != session) return false
        if (sequence < synchronizedSequence || sequence < appliedSequence) return false
        sessionID = session
        synchronizedSequence = sequence
        expectedResources = resources
        return true
    }

    fun acceptState(session: String, sequence: Long, resources: Map<String, String>): Boolean {
        if (session != sessionID || sequence < synchronizedSequence || sequence <= appliedSequence) return false
        if (!expectedResources.all { (name, revision) -> resources[name] == revision }) return false
        appliedSequence = sequence
        return true
    }
}
