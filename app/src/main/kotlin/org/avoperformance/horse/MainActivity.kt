package org.avoperformance.horse

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.content.Intent
import android.net.Uri
import android.nfc.NfcAdapter
import android.nfc.tech.Ndef
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Waves
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.delay
import org.avoperformance.horse.ui.screens.AvoBootScreen
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.core.content.ContextCompat
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import org.avoperformance.horse.ui.screens.BluetoothScreen
import org.avoperformance.horse.ui.screens.DeviceManagerScreen
import org.avoperformance.horse.ui.screens.DiagnosticsScreen
import org.avoperformance.horse.ui.screens.GeofencesScreen
import org.avoperformance.horse.ui.screens.HistoryScreen
import org.avoperformance.horse.ui.screens.HomeScreen
import org.avoperformance.horse.ui.screens.HorsesScreen
import org.avoperformance.horse.ui.screens.NfcScreen
import org.avoperformance.horse.ui.screens.TidesScreen
import org.avoperformance.horse.ui.screens.NtripScreen
import org.avoperformance.horse.ui.screens.RidersScreen
import org.avoperformance.horse.ui.screens.SettingsScreen
import org.avoperformance.horse.ui.screens.StorageScreen
import org.avoperformance.horse.ui.screens.SyncScreen
import org.avoperformance.horse.ui.screens.TrainingDetailScreen
import org.avoperformance.horse.ui.screens.CompareScreen
import org.avoperformance.horse.ui.screens.TrainingScreen
import org.avoperformance.horse.ui.theme.AvoColors
import org.avoperformance.horse.ui.theme.AvoTheme

object Perms {
    val required: Array<String> get() = buildList {
        if (Build.VERSION.SDK_INT >= 31) { add(Manifest.permission.BLUETOOTH_SCAN); add(Manifest.permission.BLUETOOTH_CONNECT) }
        else add(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }.toTypedArray()

    fun bluetoothGranted(a: android.content.Context): Boolean = required
        .filter { it != Manifest.permission.POST_NOTIFICATIONS }
        .all { ContextCompat.checkSelfPermission(a, it) == PackageManager.PERMISSION_GRANTED }
}

class MainActivity : ComponentActivity() {
    private val nfcAdapter by lazy { NfcAdapter.getDefaultAdapter(this) }
    private var nfcReadBusy = java.util.concurrent.atomic.AtomicBoolean(false)
    private var lastNfcRead = 0L

    /** NFC identity reader stays active on every AVO screen while the activity is resumed. */
    fun enableGlobalNfc() {
        if (nfcAdapter?.isEnabled != true || !lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) return
        nfcAdapter?.enableReaderMode(this, NfcAdapter.ReaderCallback { tag ->
            val now = android.os.SystemClock.elapsedRealtime()
            if (now - lastNfcRead < 1500L || !nfcReadBusy.compareAndSet(false, true)) return@ReaderCallback
            lastNfcRead = now
            lifecycleScope.launch {
                try {
                    val uri = withContext(Dispatchers.IO) {
                        val ndef = Ndef.get(tag) ?: return@withContext null
                        ndef.connect()
                        try { ndef.ndefMessage?.records?.firstNotNullOfOrNull { it.toUri() } }
                        finally { ndef.close() }
                    }
                    if (uri?.scheme != "avohorse" || uri.host != "identity") return@launch
                    if (uri.pathSegments.getOrNull(0) == "user") { onUserCard(uri.toString()); return@launch }
                    val type = uri.pathSegments.getOrNull(0)
                    val code = uri.pathSegments.getOrNull(1) ?: return@launch
                    if (type != "horse" && type != "rider") return@launch
                    val c = (application as AvoApp).container
                    val status = c.watch.status.value
                    if (status?.session == org.avoperformance.horse.core.ble.WatchSessionState.RECORDING ||
                        status?.session == org.avoperformance.horse.core.ble.WatchSessionState.PAUSED ||
                        status?.rec == org.avoperformance.horse.core.ble.RecStatus.RECORDING) {
                        android.widget.Toast.makeText(this@MainActivity, "NFC: entrenamiento activo; no se cambia identidad", android.widget.Toast.LENGTH_LONG).show()
                        return@launch
                    }
                    val horse = withContext(Dispatchers.IO) { c.db.horses().all().first().firstOrNull { it.code == code } }
                    val rider = withContext(Dispatchers.IO) { c.db.riders().all().first().firstOrNull { it.code == code } }
                    val horseId = if (type == "horse") horse?.id ?: withContext(Dispatchers.IO) {
                        org.avoperformance.horse.core.nfc.AvoNfc.import(uri, c.db)
                    } else c.settings.selectedHorseId
                    val riderId = if (type == "rider") rider?.id ?: withContext(Dispatchers.IO) {
                        org.avoperformance.horse.core.nfc.AvoNfc.import(uri, c.db)
                    } else c.settings.selectedRiderId
                    if (type == "horse") c.settings.selectedHorseId = horseId
                    if (type == "rider") c.settings.selectedRiderId = riderId
                    val selectedHorse = withContext(Dispatchers.IO) { c.db.horses().byId(horseId) }
                    val selectedRider = withContext(Dispatchers.IO) { c.db.riders().byId(riderId) }
                    val feedback = if (selectedHorse == null || selectedRider == null) "NFC guardado; falta seleccionar caballo o jinete"
                        else {
                            val error = withContext(Dispatchers.IO) { c.config.setIdentity(selectedHorse.id, selectedHorse.code, selectedRider.id, selectedRider.code) }
                            if (error == null) "NFC: identidad enviada al reloj" else "NFC seleccionado; BLE: $error"
                        }
                    android.widget.Toast.makeText(this@MainActivity, feedback, android.widget.Toast.LENGTH_LONG).show()
                } catch (e: Exception) {
                    android.widget.Toast.makeText(this@MainActivity, "NFC: ${e.message ?: "error de lectura"}", android.widget.Toast.LENGTH_LONG).show()
                } finally { nfcReadBusy.set(false) }
            }
        }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B, null)
    }

    override fun onResume() {
        super.onResume()
        enableGlobalNfc()
        // recovery when the app opens: pending deliveries and received trainings
        (application as AvoApp).container.let { c -> if (c.identity.card.value != null) { c.share.schedule(); c.share.runNow() } }
    }

    override fun onPause() {
        nfcAdapter?.disableReaderMode(this)
        super.onPause()
    }

    private var incomingAvo by mutableStateOf<Uri?>(null)
    private var openShare by mutableStateOf(false)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingAvo = extractAvoUri(intent)
        if (intent.action == org.avoperformance.horse.cloud.ShareManager.ACTION_OPEN_SHARE) openShare = true
        handleSystemNfc(intent)
    }

    /** AVO user card: adopted as the phone identity only if there is none (see UserIdentity). */
    private fun onUserCard(uri: String) {
        val c = (application as AvoApp).container
        val text = try { c.identity.message(c.identity.onCardTapped(uri)) } catch (e: Exception) { "NFC: ${e.message ?: "tarjeta no válida"}" }
        runOnUiThread { android.widget.Toast.makeText(this, text, android.widget.Toast.LENGTH_LONG).show() }
    }

    private fun handleSystemNfc(intent: Intent?) {
        if (intent?.action != NfcAdapter.ACTION_NDEF_DISCOVERED) return
        val uri = intent.data ?: return
        if (uri.scheme != "avohorse" || uri.host != "identity") return
        if (uri.pathSegments.getOrNull(0) == "user") { onUserCard(uri.toString()); return }
        val type = uri.pathSegments.getOrNull(0)
        val code = uri.pathSegments.getOrNull(1) ?: return
        if (type !in listOf("horse", "rider")) return
        lifecycleScope.launch {
            try {
                val c = (application as AvoApp).container
                val status = c.watch.status.value
                if (status?.session == org.avoperformance.horse.core.ble.WatchSessionState.RECORDING ||
                    status?.session == org.avoperformance.horse.core.ble.WatchSessionState.PAUSED ||
                    status?.rec == org.avoperformance.horse.core.ble.RecStatus.RECORDING) {
                    android.widget.Toast.makeText(this@MainActivity, "NFC: sesión activa", android.widget.Toast.LENGTH_LONG).show()
                    return@launch
                }
                val horse = withContext(Dispatchers.IO) { c.db.horses().all().first().firstOrNull { it.code == code } }
                val rider = withContext(Dispatchers.IO) { c.db.riders().all().first().firstOrNull { it.code == code } }
                val horseId = if (type == "horse") horse?.id ?: withContext(Dispatchers.IO) {
                    c.db.horses().insert(org.avoperformance.horse.data.HorseEntity(code = code, name = code))
                } else c.settings.selectedHorseId
                val riderId = if (type == "rider") rider?.id ?: withContext(Dispatchers.IO) {
                    c.db.riders().insert(org.avoperformance.horse.data.RiderEntity(code = code, name = code))
                } else c.settings.selectedRiderId
                if (type == "horse") c.settings.selectedHorseId = horseId
                if (type == "rider") c.settings.selectedRiderId = riderId
                val h = withContext(Dispatchers.IO) { c.db.horses().byId(horseId) }
                val j = withContext(Dispatchers.IO) { c.db.riders().byId(riderId) }
                val error = if (h != null && j != null) withContext(Dispatchers.IO) { c.config.setIdentity(h.id, h.code, j.id, j.code) } else "falta caballo o jinete"
                android.widget.Toast.makeText(this@MainActivity, if (error == null) "NFC: identidad enviada al reloj" else "NFC seleccionada; $error", android.widget.Toast.LENGTH_LONG).show()
            } catch (e: Exception) {
                android.widget.Toast.makeText(this@MainActivity, "NFC: ${e.message ?: "error"}", android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun extractAvoUri(intent: Intent?): Uri? = when (intent?.action) {
        Intent.ACTION_VIEW -> intent.data
        Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33)
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        else -> null
    }
    private val permLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val c = (application as AvoApp).container
        incomingAvo = extractAvoUri(intent)
        if (intent?.action == org.avoperformance.horse.cloud.ShareManager.ACTION_OPEN_SHARE) openShare = true
        handleSystemNfc(intent)
        if (!Perms.bluetoothGranted(this)) permLauncher.launch(Perms.required)
        else org.avoperformance.horse.service.AvoLinkService.startIfAutomatic(this, "app abierta")
        setContent {
            AvoTheme {
                var bootVisible by rememberSaveable { mutableStateOf(savedInstanceState == null) }
                LaunchedEffect(Unit) { delay(3000L); bootVisible = false }
                if (bootVisible) AvoBootScreen(c, onContinue = { bootVisible = false })
                else AvoNav(c, incomingAvo, onImportHandled = { incomingAvo = null }, openShare = openShare, onShareOpened = { openShare = false }) { permLauncher.launch(Perms.required) }
            }
        }
    }
}

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("inicio", "Inicio", Icons.Filled.Home),
    Tab("entrenamiento", "Entrenar", Icons.Filled.PlayArrow),
    Tab("historial", "Historial", Icons.AutoMirrored.Filled.List),
    Tab("mareas", "Mareas", Icons.Filled.Waves),
    Tab("caballos", "Cuadra", Icons.Filled.Favorite),
)

private val titles = mapOf(
    "configuracion" to "Ajustes", "nfc" to "NFC", "bluetooth" to "Bluetooth", "ntrip" to "NTRIP", "geocercas" to "Geocercas", "sincronizacion" to "Sincronización",
    "diagnosticos" to "Diagnósticos", "dispositivos" to "Dispositivos", "almacenamiento" to "Almacenamiento", "jinetes" to "Jinetes", "compartir" to "Compartir y sincronizar", "detalle/{id}" to "Análisis", "comparar/{a}/{b}" to "Comparativa",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AvoNav(c: AppContainer, incomingAvo: Uri? = null, onImportHandled: () -> Unit = {}, openShare: Boolean = false, onShareOpened: () -> Unit = {}, requestPerms: () -> Unit) {
    val nav = rememberNavController()
    LaunchedEffect(incomingAvo) { if (incomingAvo != null) nav.navigate("historial") { launchSingleTop = true } }
    LaunchedEffect(openShare) { if (openShare) { nav.navigate("compartir") { launchSingleTop = true }; onShareOpened() } }
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val isTab = tabs.any { it.route == route }
    Scaffold(
        containerColor = AvoColors.Bg,
        topBar = {
            TopAppBar(
                title = {
                    if (isTab) Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("AVO", color = AvoColors.Red, fontWeight = FontWeight.Black, fontSize = 22.sp, letterSpacing = 2.sp)
                        Spacer(Modifier.width(10.dp))
                        Text(tabs.first { it.route == route }.label.uppercase(), color = AvoColors.Text, fontWeight = FontWeight.Bold, fontSize = 16.sp, letterSpacing = 1.5.sp)
                    } else Text((titles[route] ?: "AVO").uppercase(), fontWeight = FontWeight.Bold, fontSize = 17.sp, letterSpacing = 1.2.sp)
                },
                navigationIcon = { if (!isTab && route != null) IconButton(onClick = { nav.popBackStack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Atrás") } },
                actions = { if (isTab) IconButton(onClick = { nav.navigate("configuracion") { launchSingleTop = true } }) { Icon(Icons.Filled.Settings, "Ajustes", tint = AvoColors.Silver) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AvoColors.Bg, titleContentColor = AvoColors.Text, navigationIconContentColor = AvoColors.Text),
            )
        },
        bottomBar = {
            if (isTab) Column {
                HorizontalDivider(color = AvoColors.Line, thickness = 0.5.dp)
                NavigationBar(containerColor = AvoColors.Bg, tonalElevation = 0.dp) {
                    tabs.forEach { t ->
                        NavigationBarItem(
                            selected = route == t.route,
                            onClick = { nav.navigate(t.route) { popUpTo("inicio") { saveState = true }; launchSingleTop = true; restoreState = true } },
                            icon = { Icon(t.icon, t.label) },
                            label = { Text(t.label, maxLines = 1, fontSize = 11.sp) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = Color.White, selectedTextColor = AvoColors.Red, indicatorColor = AvoColors.Red,
                                unselectedIconColor = AvoColors.TextDim, unselectedTextColor = AvoColors.TextDim),
                        )
                    }
                }
            }
        },
    ) { pad ->
        NavHost(nav, startDestination = "inicio", modifier = Modifier.padding(pad)) {
            composable("inicio") { HomeScreen(c, go(nav)) }
            composable("entrenamiento") { TrainingScreen(c, go(nav)) }
            composable("historial") { HistoryScreen(c, go(nav), incomingAvo, onImportHandled) }
            composable("caballos") { HorsesScreen(c, go(nav)) }
            composable("configuracion") { SettingsScreen(c, go(nav)) }
            composable("bluetooth") { BluetoothScreen(c, requestPerms) }
            composable("ntrip") { NtripScreen(c) }
            composable("nfc") { NfcScreen(c) }
            composable("mareas") { TidesScreen(c) }
            composable("geocercas") { GeofencesScreen(c) }
            composable("sincronizacion") { SyncScreen(c) }
            composable("diagnosticos") { DiagnosticsScreen(c) }
            composable("dispositivos") { DeviceManagerScreen(c) }
            composable("almacenamiento") { StorageScreen(c) }
            composable("jinetes") { RidersScreen(c) }
            composable("compartir") { org.avoperformance.horse.ui.screens.ShareScreen(c) }
            composable("comparar/{a}/{b}") { back -> CompareScreen(c, back.arguments?.getString("a") ?: "", back.arguments?.getString("b") ?: "") }
            composable("detalle/{id}") { TrainingDetailScreen(c, it.arguments?.getString("id") ?: "") }
        }
    }
}

private fun go(nav: NavHostController): (String) -> Unit = { nav.navigate(it) }
