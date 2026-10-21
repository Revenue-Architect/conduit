package app.cogwheel.conduit.push

import org.junit.Assert.*
import org.junit.Test

class PushInboxPageTest {
    private val cursor = "01JABCDEFGHJKMNPQRSTVWXYZ0"
    private val envelope = """{"v":1,"t":"notify","id":"inbox1","ts":1760841600,"cat":"alerts","ack":true}"""

    @Test fun parsesPageAndRetainsAuthenticatedEnvelope() {
        val page = PushInboxPage.parse("""{"items":[$envelope],"next":"$cursor","more":true}""")!!
        assertEquals(cursor, page.next)
        assertTrue(page.more)
        assertTrue(page.envelopes.single().first.ack)
    }

    @Test fun emptyInboxDoesNotInventCursor() {
        val page = PushInboxPage.parse("""{"items":[],"next":null,"more":false}""")!!
        assertNull(page.next)
        assertFalse(page.more)
    }

    @Test fun malformedPageNeverAdvancesCursor() {
        assertNull(PushInboxPage.parse("""{"items":[$envelope,{}],"next":"$cursor","more":false}"""))
        assertNull(PushInboxPage.parse("""{"items":[],"next":"bad","more":true}"""))
        assertNull(PushInboxPage.parse("""{"items":[],"next":"$cursor","more":true}"""))
    }

    @Test fun rejectsShadowAndVerificationInReplay() {
        val shadow = envelope.replace("\"ack\":true", "\"shadow\":true")
        assertNull(PushInboxPage.parse("""{"items":[$shadow],"next":"$cursor","more":false}"""))
    }
}
