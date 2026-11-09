package example;

import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;

class ReportTest {
    private static int flakyAttempts = 0;
    private static boolean candidate() {
        return "candidate".equals(System.getProperty("delta.stage"));
    }

    @Test void stable() { assertEquals(4, 2 + 2); }
    @Test void newFailure() { assertFalse(candidate(), "new regression <api> & 参数😀"); }
    @Test void fixedFailure() { assertTrue(candidate(), "fixed in the candidate"); }
    @Test void persistentFailure() { fail("persistent failure"); }
    @Test @Disabled("intentional skip") void skipped() {}
    @Test void flaky() { assertTrue(++flakyAttempts > 1, "first attempt fails"); }
    @Test void error() { throw new IllegalStateException("intentional runtime error"); }

    @ParameterizedTest
    @ValueSource(strings = {"ASCII", "参数😀"})
    void parameters(String value) { assertFalse(candidate() && !value.equals("ASCII")); }
}
