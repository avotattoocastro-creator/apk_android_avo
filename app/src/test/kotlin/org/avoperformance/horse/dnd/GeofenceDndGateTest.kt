package org.avoperformance.horse.dnd

import org.avoperformance.horse.core.ble.GeofenceState
import org.avoperformance.horse.core.ble.WatchSessionState
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeofenceDndGateTest {
    @Test fun automaticGeofenceRecordingEnablesDnd() {
        assertTrue(GeofenceDndGate.shouldSilence(WatchSessionState.RECORDING, GeofenceState.RECORDING, false))
        assertTrue(GeofenceDndGate.shouldSilence(WatchSessionState.RECORDING, GeofenceState.EXIT_PENDING, false))
        assertTrue(GeofenceDndGate.shouldSilence(WatchSessionState.PAUSED, GeofenceState.PAUSED, false))
    }

    @Test fun manualRecordingNeverEnablesDnd() {
        assertFalse(GeofenceDndGate.shouldSilence(WatchSessionState.RECORDING, GeofenceState.RECORDING, true))
        assertFalse(GeofenceDndGate.shouldSilence(WatchSessionState.PAUSED, GeofenceState.PAUSED, true))
    }

    @Test fun positionAloneNeverEnablesDnd() {
        assertFalse(GeofenceDndGate.shouldSilence(WatchSessionState.IDLE, GeofenceState.INSIDE, false))
        assertFalse(GeofenceDndGate.shouldSilence(WatchSessionState.ARMED, GeofenceState.ENTRY_PENDING, false))
        assertFalse(GeofenceDndGate.shouldSilence(WatchSessionState.RECORDING, GeofenceState.OUTSIDE, false))
        assertFalse(GeofenceDndGate.shouldSilence(WatchSessionState.COMPLETED, GeofenceState.RECORDING, false))
    }

    @Test fun staleAndFutureTelemetryAreRejected() {
        assertTrue(GeofenceDndGate.isFresh(10000L, 14999L))
        assertFalse(GeofenceDndGate.isFresh(10000L, 15001L))
        assertFalse(GeofenceDndGate.isFresh(10000L, 9999L))
        assertFalse(GeofenceDndGate.isFresh(0L, 100L))
    }

    @Test fun legacyGeofenceRecordingIsSupportedWhenManualFlagUnknown() {
        assertTrue(GeofenceDndGate.shouldSilence(WatchSessionState.RECORDING, GeofenceState.RECORDING, null))
    }
}
