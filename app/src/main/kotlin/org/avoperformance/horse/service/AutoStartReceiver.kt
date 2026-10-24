package org.avoperformance.horse.service

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.avoperformance.horse.AvoApp

/**
 * Starts the AVO link service in the background so the app works without being opened:
 * after boot, after an app update, when Bluetooth is switched on, and when the phone links with the authorised watch.
 */
class AutoStartReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> AvoLinkService.startIfAutomatic(ctx, intent.action ?: "")
            BluetoothAdapter.ACTION_STATE_CHANGED ->
                if (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1) == BluetoothAdapter.STATE_ON) AvoLinkService.startIfAutomatic(ctx, "Bluetooth activado")
            BluetoothDevice.ACTION_ACL_CONNECTED -> {
                val dev: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    else @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                val watch = (ctx.applicationContext as AvoApp).container.settings.authorizedWatch
                if (dev != null && watch != null && dev.address.equals(watch, ignoreCase = true)) AvoLinkService.startIfAutomatic(ctx, "reloj enlazado")
            }
        }
    }
}
