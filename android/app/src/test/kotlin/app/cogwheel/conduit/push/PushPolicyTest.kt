package app.cogwheel.conduit.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PushPolicyTest {
    private fun envelope(ts: Long, ttl: Long, cat: String = "alerts") = PushEnvelope.parse(
        """{"v":1,"t":"notify","id":"e1","ts":$ts,"ttl":$ttl,"cat":"$cat"}""".toByteArray(),
    )!!

    @Test
    fun expiryHonorsTtlWithClockSkewAllowance() {
        val e = envelope(ts = 1_000_000, ttl = 100)
        assertFalse(PushPolicy.isExpired(e, 1_000_050))
        assertFalse(PushPolicy.isExpired(e, 1_000_100 + PushLimits.CLOCK_SKEW_SECONDS))
        assertTrue(PushPolicy.isExpired(e, 1_000_100 + PushLimits.CLOCK_SKEW_SECONDS + 1))
    }

    @Test
    fun masterSwitchSilencesEverything() {
        for (c in PushCategory.entries) assertFalse(PushPolicy.isCategoryAllowed(c, false, emptySet()))
    }

    @Test
    fun approvalsAndCriticalIgnorePerCategoryOffSwitches() {
        val off = PushCategory.entries.map { it.wire }.toSet()
        assertTrue(PushPolicy.isCategoryAllowed(PushCategory.APPROVALS, true, off))
        assertTrue(PushPolicy.isCategoryAllowed(PushCategory.CRITICAL, true, off))
        assertFalse(PushPolicy.isCategoryAllowed(PushCategory.BRIEFS, true, off))
        assertTrue(PushPolicy.isCategoryAllowed(PushCategory.BRIEFS, true, setOf("alerts")))
    }

    @Test
    fun backoffDoublesFromThirtySecondsAndCaps() {
        assertEquals(30L, PushPolicy.backoffSeconds(1))
        assertEquals(60L, PushPolicy.backoffSeconds(2))
        assertEquals(120L, PushPolicy.backoffSeconds(3))
        assertEquals(1800L, PushPolicy.backoffSeconds(50))
    }

    @Test
    fun decisionResponsesAreClassified() {
        assertEquals(DecisionOutcome.DONE, PushPolicy.classifyDecisionResponse(200))
        assertEquals(DecisionOutcome.CONFLICT, PushPolicy.classifyDecisionResponse(409))
        assertEquals(DecisionOutcome.GONE, PushPolicy.classifyDecisionResponse(404))
        assertEquals(DecisionOutcome.UNAUTHORIZED, PushPolicy.classifyDecisionResponse(401))
        assertEquals(DecisionOutcome.UNAUTHORIZED, PushPolicy.classifyDecisionResponse(403))
        assertEquals(DecisionOutcome.RETRY, PushPolicy.classifyDecisionResponse(503))
        assertEquals(DecisionOutcome.RETRY, PushPolicy.classifyDecisionResponse(429))
        assertEquals(DecisionOutcome.REJECTED, PushPolicy.classifyDecisionResponse(400))
    }

    @Test
    fun statusWordsMapV2Statuses() {
        assertEquals(StatusWord.APPROVED, PushPolicy.statusWord("approved"))
        assertEquals(StatusWord.DENIED, PushPolicy.statusWord("denied"))
        assertEquals(StatusWord.EXPIRED, PushPolicy.statusWord("EXPIRED"))
        assertEquals(StatusWord.PENDING, PushPolicy.statusWord("pending"))
        assertEquals(StatusWord.UNKNOWN, PushPolicy.statusWord(null))
    }

    @Test
    fun dedupSetRemembersAndEvictsOldest() {
        val set = DedupSet.parse(null, capacity = 3)
        assertTrue(set.markFresh("a"))
        assertFalse(set.markFresh("a"))
        set.markFresh("b"); set.markFresh("c"); set.markFresh("d")
        assertEquals(3, set.size)
        assertFalse(set.contains("a"))
        assertTrue(set.contains("d"))
    }

    @Test
    fun dedupSetSurvivesSerialization() {
        val set = DedupSet.parse(null)
        set.markFresh("x1"); set.markFresh("x2")
        val restored = DedupSet.parse(set.serialize())
        assertFalse(restored.markFresh("x1"))
        assertTrue(restored.markFresh("x3"))
    }

    @Test
    fun deepLinksMatchTheAppRoutes() {
        val approval = PushOpen(OpenKind.APPROVAL, "abc-123", null)
        assertEquals("hermez://hermes/profile/hermes/approvals/abc-123", PushDeepLinks.forOpen(approval))
        assertEquals("hermez://hermes/profile/hermes/live/s1", PushDeepLinks.forOpen(PushOpen(OpenKind.SESSION, "s1", null)))
        assertEquals("hermez://hermes/profile/hermes/conversations?thread=7", PushDeepLinks.forOpen(PushOpen(OpenKind.THREAD, "7", null)))
        assertEquals("hermez://hermes/profile/hermes/home?brief=2026-10-19", PushDeepLinks.forOpen(PushOpen(OpenKind.BRIEF, "2026-10-19", null)))
        assertNull(PushDeepLinks.forOpen(PushOpen(OpenKind.NONE, null, null)))
        assertNull(PushDeepLinks.forOpen(null))
    }

    @Test
    fun shadeTextCoversEveryOutcome() {
        assertEquals("Approved: restart it", PushShadeText.decided(StatusWord.APPROVED, "restart it"))
        assertEquals("Denied", PushShadeText.decided(StatusWord.DENIED, null))
        assertEquals("Expired", PushShadeText.decided(StatusWord.EXPIRED, ""))
        assertEquals("Already decided", PushShadeText.decided(StatusWord.UNKNOWN, null))
        assertEquals("Approving…", PushShadeText.sending("approve"))
        assertEquals("Denying…", PushShadeText.sending("deny"))
    }
}
