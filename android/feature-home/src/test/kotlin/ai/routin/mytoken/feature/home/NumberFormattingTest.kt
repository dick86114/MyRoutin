package ai.routin.mytoken.feature.home

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Test

class NumberFormattingTest {
    @Test
    fun decimalValuesRoundToAtMostTwoFractionDigits() {
        assertEquals("12.35", formatDecimal(BigDecimal("12.345")))
        assertEquals("12.34", formatDecimal(BigDecimal("12.344")))
        assertEquals("7", formatDecimal(BigDecimal("7")))
    }

    @Test
    fun compactValuesKeepAtMostTwoFractionDigits() {
        assertEquals("4.57K", formatCompact(BigDecimal("4567")))
        assertEquals("0.13", formatCompact(BigDecimal("0.1342")))
        assertEquals("120K", formatCompact(BigDecimal("120000")))
    }

    @Test
    fun percentValuesKeepAtMostTwoFractionDigits() {
        assertEquals("0.13%", formatPercent(0.1342))
        assertEquals("67.56%", formatPercent(67.555))
        assertEquals("42%", formatPercent(42.0))
    }
}
