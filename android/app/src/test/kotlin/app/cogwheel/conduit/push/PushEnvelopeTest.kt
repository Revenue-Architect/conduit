package app.cogwheel.conduit.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PushEnvelopeTest {
    private val approval = "60867a2f-afa1-4679-b9de-672d1a17ac63"
    private val digest = "a".repeat(64)

    private fun parse(json: String) = PushEnvelope.parse(json.toByteArray(Charsets.UTF_8))

    private fun approvalJson(extra: String = "") = """
        {"v":1,"t":"notify","id":"01JABCDEFGHJKMNPQRSTVWXYZ0","dedupe":"approval:$approval:created",
         "tag":"approval:$approval","ts":1760841600,"ttl":86400,"cat":"approvals","pri":4,
         "title":"Approval needed: restart_container","body":"Restart it\nAnswer by 3:40 PM",
         "open":{"k":"approval","id":"$approval"},
         "actions":[
           {"id":"approve","label":"Approve","kind":"decide","approval":"$approval","digest":"$digest","auth":true},
           {"id":"deny","label":"Deny","kind":"decide","approval":"$approval","digest":"$digest","auth":false}
         ],"group":"approvals","ack":true,"shadow":false$extra}
    """.trimIndent()

    @Test
    fun parsesTheSpecApprovalExample() {
        val e = parse(approvalJson())!!
        assertEquals(PushType.NOTIFY, e.type)
        assertEquals(PushCategory.APPROVALS, e.category)
        assertEquals("approval:$approval", e.effectiveTag)
        assertEquals(4, e.priority)
        assertTrue(e.ack)
        assertEquals(2, e.actions.size)
        assertEquals("approve", e.actions[0].decision)
        assertTrue(e.actions[0].auth)
        assertFalse(e.actions[1].auth)
        assertEquals(OpenKind.APPROVAL, e.open?.kind)
        assertEquals(approval, e.open?.id)
    }

    @Test
    fun rejectsWrongVersionUnknownTypeAndGarbage() {
        assertNull(parse("""{"v":2,"t":"notify","id":"x1","ts":1,"cat":"alerts"}"""))
        assertNull(parse("""{"v":1,"t":"explode","id":"x1","ts":1,"cat":"alerts"}"""))
        assertNull(parse("not json"))
        assertNull(parse(""))
        assertNull(PushEnvelope.parse(ByteArray(PushLimits.MAX_ENVELOPE_BYTES + 1) { 'a'.code.toByte() }))
    }

    @Test
    fun ignoresUnknownFields() {
        assertNotNull(parse("""{"v":1,"t":"notify","id":"x1","ts":1760841600,"cat":"alerts","future":{"a":1}}"""))
    }

    @Test
    fun truncatesOverlongTitleAndBody() {
        val title = "t".repeat(500)
        val body = "b".repeat(1500)
        val e = parse("""{"v":1,"t":"notify","id":"x1","ts":1760841600,"cat":"alerts","title":"$title","body":"$body"}""")!!
        assertEquals(PushLimits.MAX_TITLE, e.title.length)
        assertEquals(PushLimits.MAX_BODY, e.body.length)
    }

    @Test
    fun probeAndVerifyNeedNoCategory() {
        val probe = parse("""{"v":1,"t":"probe","id":"p1","ts":1760841600,"ack":true}""")!!
        assertEquals(PushType.PROBE, probe.type)
        val verify = parse("""{"v":1,"t":"verify","id":"v1","ts":1760841600,"nonce":"n123"}""")!!
        assertEquals("n123", verify.nonce)
        assertNull(parse("""{"v":1,"t":"verify","id":"v1","ts":1760841600}"""))
    }

    @Test
    fun dismissNeedsATag() {
        assertNull(parse("""{"v":1,"t":"dismiss","id":"d1","ts":1760841600,"cat":"approvals"}"""))
        assertNotNull(parse("""{"v":1,"t":"dismiss","id":"d1","ts":1760841600,"cat":"approvals","tag":"approval:x"}"""))
    }

    @Test
    fun dropsDecideActionsWithBadDigestOrApproval() {
        val bad = approvalJson().replace(digest, "xyz")
        val e = parse(bad)!!
        assertTrue(e.actions.isEmpty())
        val noApproval = approvalJson().replace("\"approval\":\"$approval\",\"digest\"", "\"approval\":\"\",\"digest\"")
        assertTrue(parse(noApproval)!!.actions.isEmpty())
    }

    @Test
    fun decideActionIdsAreLimitedToApproveAndDeny() {
        val e = parse(approvalJson().replace("\"id\":\"deny\"", "\"id\":\"wipe\""))!!
        assertEquals(1, e.actions.size)
        assertEquals("approve", e.actions[0].id)
    }

    @Test
    fun relayAndViewActionsMustUseThePinnedOrigin() {
        val relay = "https://umbrel.tail4c9e01.ts.net:8447/action/abc"
        val ok = parse(
            """{"v":1,"t":"notify","id":"r1","ts":1760841600,"cat":"proactive","actions":[
                {"id":"done","label":"Done","kind":"relay","url":"$relay","method":"POST"},
                {"id":"evil","label":"Evil","kind":"relay","url":"https://evil.example/action","method":"POST"},
                {"id":"look","label":"Look","kind":"view","url":"$relay"},
                {"id":"get","label":"Get","kind":"relay","url":"$relay","method":"GET"}
            ]}""",
        )!!
        assertEquals(listOf("done", "look"), ok.actions.map { it.id })
        assertTrue(PushEnvelope.isRelayUrl(relay))
        assertFalse(PushEnvelope.isRelayUrl("https://umbrel.tail4c9e01.ts.net:8447.evil.example/x"))
        assertFalse(PushEnvelope.isRelayUrl("http://umbrel.tail4c9e01.ts.net:8447/x"))
    }

    @Test
    fun urlOpenMustBeTheRelayOtherwiseTheOpenIsDropped() {
        val ok = parse("""{"v":1,"t":"notify","id":"u1","ts":1760841600,"cat":"alerts","open":{"k":"url","url":"https://umbrel.tail4c9e01.ts.net:8447/page"}}""")!!
        assertEquals(OpenKind.URL, ok.open?.kind)
        val evil = parse("""{"v":1,"t":"notify","id":"u2","ts":1760841600,"cat":"alerts","open":{"k":"url","url":"https://evil.example/"}}""")!!
        assertNull(evil.open)
    }

    @Test
    fun clampsPriorityAndTtl() {
        val e = parse("""{"v":1,"t":"notify","id":"c1","ts":1760841600,"cat":"alerts","pri":99,"ttl":99999999}""")!!
        assertEquals(5, e.priority)
        assertEquals(PushLimits.MAX_TTL_SECONDS, e.ttl)
    }

    @Test
    fun capsTheNumberOfActions() {
        val actions = (1..6).joinToString(",") { """{"id":"a$it","label":"L$it","kind":"view","url":"https://umbrel.tail4c9e01.ts.net:8447/$it"}""" }
        val e = parse("""{"v":1,"t":"notify","id":"m1","ts":1760841600,"cat":"alerts","actions":[$actions]}""")!!
        assertEquals(PushLimits.MAX_ACTIONS, e.actions.size)
    }

    @Test
    fun idsWithPathCharactersAreRejected() {
        assertNull(parse("""{"v":1,"t":"notify","id":"../etc","ts":1760841600,"cat":"alerts"}"""))
        assertNull(parse("""{"v":1,"t":"notify","id":"ok","tag":"has space","ts":1760841600,"cat":"alerts"}"""))
    }
}
