package app.cogwheel.conduit

import org.junit.Assert.*
import org.junit.Test

class TextSharingTest {
    @Test fun acknowledgmentMustCoverTheWholeBatch() {
        assertTrue(acknowledgedBatch(202, 500, 500))
        assertFalse(acknowledgedBatch(200, 500, 500))
        assertFalse(acknowledgedBatch(202, 499, 500))
    }
    @Test fun codesAndShortCodesAreFilteredBeforeTransport() {
        assertTrue(isFilteredText("Your verification code is 123456", "+14165551234"))
        assertTrue(isFilteredText("123456 is your login code", "+14165551234"))
        assertTrue(isFilteredText("Your OTP: 483921", "+14165551234"))
        assertTrue(isFilteredText("Check your plan", "12345"))
        assertFalse(isFilteredText("The doorbell is silent indoors", "+14165551234"))
    }
    @Test fun savedContactsKeepCodeShapedRealMessages() {
        // Claude QA: these were silently dropped before.
        assertFalse(isFilteredText("The security deposit is 2000, can you send it?", "+14165551234", knownContact = true))
        assertFalse(isFilteredText("confirmation 4821 is what they gave me", "+14165551234", outgoing = true))
        assertTrue(isFilteredText("Your verification code is 123456", "+14165551234", knownContact = true))
        assertTrue(isFilteredText("The security deposit is 2000", "+14165551234"))  // stranger: still filtered
    }
    @Test fun longMessagesAreClippedWithinTheRelayLimit() {
        val (short, clipped) = clipText("hello")
        assertEquals("hello", short); assertFalse(clipped)
        val (body, truncated) = clipText("é".repeat(9000))
        assertTrue(truncated); assertTrue(body.toByteArray().size <= 8000); assertTrue(body.endsWith("[…message truncated]"))
        val (emoji, _) = clipText("😀".repeat(5000))
        assertFalse(Character.isHighSurrogate(emoji[emoji.length - " […message truncated]".length - 1]))
    }
}
