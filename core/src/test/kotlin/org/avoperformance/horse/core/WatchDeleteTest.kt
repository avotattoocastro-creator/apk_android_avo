package org.avoperformance.horse.core

import org.avoperformance.horse.core.ble.WatchFileState
import org.avoperformance.horse.core.sync.LocalTraining
import org.avoperformance.horse.core.sync.SyncState
import org.avoperformance.horse.core.sync.WatchDelete
import org.junit.Assert.*
import org.junit.Test

class WatchDeleteTest {
    private fun t(id: String, state: SyncState, local: String? = null, watch: String? = null, ws: WatchFileState = WatchFileState.CLOSED) =
        LocalTraining(id, 1, 1000, if (local != null) 1000 else 0, local, watch, null, state, ws, 0, 0)

    @Test fun passwordIsExactlyAvo() {
        assertTrue(WatchDelete.passwordOk("AVO"))
        assertTrue(WatchDelete.passwordOk("  AVO "))
        assertFalse(WatchDelete.passwordOk("avo"))
        assertFalse(WatchDelete.passwordOk("AV0"))
        assertFalse(WatchDelete.passwordOk(""))
    }

    @Test fun safetyNeedsAVerifiedCopy() {
        assertEquals(WatchDelete.Safety.COPIA_EN_MOVIL, WatchDelete.safety(t("a", SyncState.VERIFICADO_LOCAL, "ab12", "AB12")))
        assertEquals(WatchDelete.Safety.SE_PIERDE, WatchDelete.safety(t("b", SyncState.EN_RELOJ)))
        assertEquals(WatchDelete.Safety.SE_PIERDE, WatchDelete.safety(t("c", SyncState.DESCARGADO, "ab12", null)))
        assertEquals(WatchDelete.Safety.SE_PIERDE, WatchDelete.safety(t("d", SyncState.ERROR_INTEGRIDAD, "ab12", "cd34")))
        assertEquals(WatchDelete.Safety.SE_PIERDE, WatchDelete.safety(t("e", SyncState.VERIFICADO_LOCAL, "ab12", "cd34")))
    }

    @Test fun neverWhileRecordingNorTwice() {
        assertFalse(WatchDelete.canDelete(t("a", SyncState.GRABANDO), "OPEN"))
        assertFalse(WatchDelete.canDelete(t("b", SyncState.EN_RELOJ, ws = WatchFileState.OPEN), "OPEN"))
        assertFalse(WatchDelete.canDelete(t("c", SyncState.VERIFICADO_LOCAL, "x", "x"), WatchDelete.DELETED_ON_WATCH))
        assertFalse(WatchDelete.canDelete(t("d", SyncState.VERIFICADO_LOCAL, "x", "x"), "IMPORTADO"))
        assertTrue(WatchDelete.canDelete(t("e", SyncState.EN_RELOJ), "CLOSED"))
    }

    @Test fun freeableOnlyKeepsSafeOnes() {
        val list = listOf(
            t("ok", SyncState.VERIFICADO_LOCAL, "aa", "aa") to "CLOSED",
            t("solo_reloj", SyncState.EN_RELOJ) to "CLOSED",
            t("ya_borrado", SyncState.VERIFICADO_LOCAL, "bb", "bb") to WatchDelete.DELETED_ON_WATCH,
            t("grabando", SyncState.GRABANDO) to "OPEN",
        )
        assertEquals(listOf("ok"), WatchDelete.freeable(list).map { it.sessionId })
    }
}
