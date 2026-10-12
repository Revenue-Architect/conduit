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
}
