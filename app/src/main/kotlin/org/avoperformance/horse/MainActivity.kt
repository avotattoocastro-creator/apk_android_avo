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
import org.avoperformance.horse.ui.screens.LicenseNotice
import org.avoperformance.horse.ui.screens.LicenseScreen
import org.avoperformance.horse.ui.screens.LockedFeature
import org.avoperformance.horse.ui.screens.RestrictedHome
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
                    val msg = withContext(Dispatchers.IO) {
                        val ndef = Ndef.get(tag) ?: return@withContext null
                        ndef.connect()
                        try { ndef.ndefMessage } finally { ndef.close() }
                    }
                    val uri = msg?.records?.firstNotNullOfOrNull { it.toUri() }
                    if (uri?.scheme != "avohorse" || uri.host != "identity") return@launch
                    if (uri.pathSegments.getOrNull(0) == "user") { onUserCard(uri.toString(), licenseOf(msg), tag.id); return@launch }
                    val type = uri.pathSegments.getOrNull(0)
                    val code = uri.pathSegments.getOrNull(1) ?: return@launch
                    if (type != "horse" && type != "rider") return@launch
                    val c = (application as AvoApp).container
                    if (!c.license.fullAccess) {
                        android.widget.Toast.makeText(this@MainActivity, "NFC: ${org.avoperformance.horse.license.LicenseGate.BLOCKED}", android.widget.Toast.LENGTH_LONG).show()
                        return@launch
                    }
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
        (application as AvoApp).container.license.refresh()
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
    private var openLicense by mutableStateOf(false)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        routeIncoming(extractAvoUri(intent))
        if (intent.action == org.avoperformance.horse.cloud.ShareManager.ACTION_OPEN_SHARE) openShare = true
        handleSystemNfc(intent)
    }

    /** Licence record (external type avoperformance.org:lic) of a card, if any. */
    private fun licenseOf(msg: android.nfc.NdefMessage?): ByteArray? = msg?.records?.firstOrNull {
        it.tnf == android.nfc.NdefRecord.TNF_EXTERNAL_TYPE &&
            String(it.type, Charsets.US_ASCII).lowercase() == org.avoperformance.horse.core.license.LicenseToken.NDEF_EXTERNAL_TYPE
    }?.payload

    /**
     * AVO user card: adopted as the phone identity only if there is none (see UserIdentity), and its app
     * licence (signed, tied to the chip UID) is activated or renewed.
     */
    private fun onUserCard(uri: String, license: ByteArray?, tagUid: ByteArray?) {
        val c = (application as AvoApp).container
        val tapped = runCatching { org.avoperformance.horse.core.identity.AvoUserCard.parse(uri) }.getOrNull()
        val idText = try { c.identity.message(c.identity.onCardTapped(uri)) } catch (e: Exception) { "NFC: ${e.message ?: "tarjeta no válida"}" }
        val licText = runCatching { c.license.activateFromCard(license, tagUid, tapped) }.getOrElse { "Licencia: ${it.message}" }
        org.avoperformance.horse.service.AvoLinkService.startIfAutomatic(this, "tarjeta AVO")
        val text = listOfNotNull(licText, idText).joinToString("\n")
        runOnUiThread { android.widget.Toast.makeText(this, text, android.widget.Toast.LENGTH_LONG).show() }
    }

    /** A licence file (.avolic) opened from WhatsApp/email: activated here instead of being imported as a training. */
    private fun routeIncoming(uri: Uri?) {
        if (uri == null) { incomingAvo = null; return }
        lifecycleScope.launch {
            val text = withContext(Dispatchers.IO) {
                runCatching {
                    contentResolver.openInputStream(uri)?.use { s ->
                        val head = ByteArray(org.avoperformance.horse.core.license.LicenseFile.HEADER.length)
                        var n = 0
                        while (n < head.size) { val r = s.read(head, n, head.size - n); if (r < 0) break; n += r }
                        if (!org.avoperformance.horse.core.license.LicenseFile.looksLikeLicenseFile(head.copyOf(n))) null
                        else (head.copyOf(n) + s.readBytes().take(64 * 1024)).toString(Charsets.US_ASCII)
                    }
                }.getOrNull()
            }
            if (text == null) { incomingAvo = uri; return@launch }
            val c = (application as AvoApp).container
            val result = withContext(Dispatchers.Default) { c.license.activateFromFile(text, c.identity.card.value) }
            android.widget.Toast.makeText(this@MainActivity, result, android.widget.Toast.LENGTH_LONG).show()
            openLicense = true
        }
    }

    private fun handleSystemNfc(intent: Intent?) {
        if (intent?.action != NfcAdapter.ACTION_NDEF_DISCOVERED) return
        val uri = intent.data ?: return
        if (uri.scheme != "avohorse" || uri.host != "identity") return
        if (uri.pathSegments.getOrNull(0) == "user") {
            val tag: android.nfc.Tag? = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(NfcAdapter.EXTRA_TAG, android.nfc.Tag::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
            val msgs = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES, android.nfc.NdefMessage::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES)
            onUserCard(uri.toString(), licenseOf(msgs?.firstOrNull() as? android.nfc.NdefMessage), tag?.id)
            return
        }
        if (!(application as AvoApp).container.license.fullAccess) {
            android.widget.Toast.makeText(this, "NFC: ${org.avoperformance.horse.license.LicenseGate.BLOCKED}", android.widget.Toast.LENGTH_LONG).show()
            return
        }
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
        routeIncoming(extractAvoUri(intent))
        if (intent?.action == org.avoperformance.horse.cloud.ShareManager.ACTION_OPEN_SHARE) openShare = true
        handleSystemNfc(intent)
        if (!Perms.bluetoothGranted(this)) permLauncher.launch(Perms.required)
        // with a watch (Bluetooth) or, without a watch, to receive trainings from other AVO users
        org.avoperformance.horse.service.AvoLinkService.startIfAutomatic(this, "app abierta")
        setContent {
            AvoTheme {
                var bootVisible by rememberSaveable { mutableStateOf(savedInstanceState == null) }
                LaunchedEffect(Unit) { delay(3000L); bootVisible = false }
                if (bootVisible) AvoBootScreen(c, onContinue = { bootVisible = false })
                else AvoNav(c, incomingAvo, onImportHandled = { incomingAvo = null }, openShare = openShare, onShareOpened = { openShare = false },
                    openLicense = openLicense, onLicenseOpened = { openLicense = false }) { permLauncher.launch(Perms.required) }
            }
        }
    }
}

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("inicio", "Inicio", Icons.Filled.Home),
    Tab("entrenamiento", "Entrenar", Icons.Filled.PlayArrow),
    Tab("historial", "Entrenos", Icons.AutoMirrored.Filled.List),
    Tab("mareas", "Mareas", Icons.Filled.Waves),
    Tab("caballos", "Cuadra", Icons.Filled.Favorite),
)

private val titles = mapOf(
    "configuracion" to "Ajustes", "nfc" to "Tarjetas NFC", "bluetooth" to "Reloj y Bluetooth", "ntrip" to "NTRIP", "geocercas" to "Geocercas", "sincronizacion" to "Descarga del reloj",
    "diagnosticos" to "Diagnósticos", "dispositivos" to "Dispositivos", "almacenamiento" to "Almacenamiento", "jinetes" to "Jinetes", "compartir" to "Compartir y sincronizar", "lugar" to "Lugar de entrenamiento", "nomolestar" to "No molestar", "favoritos" to "WhatsApp · favoritos",
    "copias" to "Copias de seguridad", "acerca" to "Acerca de", "licencia" to "Licencia", "caballo/{code}" to "Caballo", "jinete/{code}" to "Jinete", "detalle/{id}" to "Análisis", "comparar/{a}/{b}" to "Comparativa",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AvoNav(c: AppContainer, incomingAvo: Uri? = null, onImportHandled: () -> Unit = {}, openShare: Boolean = false, onShareOpened: () -> Unit = {},
           openLicense: Boolean = false, onLicenseOpened: () -> Unit = {}, requestPerms: () -> Unit) {
    val nav = rememberNavController()
    val licenseStatus by c.license.status.collectAsStateWithLifecycle()
    val full = licenseStatus.fullAccess
    LaunchedEffect(openLicense) { if (openLicense) { nav.navigate("licencia") { launchSingleTop = true }; onLicenseOpened() } }
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
                        Text((if (route == "historial") "Entrenamientos" else tabs.first { it.route == route }.label).uppercase(), color = AvoColors.Text, fontWeight = FontWeight.Bold, fontSize = 16.sp, letterSpacing = 1.5.sp)
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
            composable("inicio") {
                if (!full) RestrictedHome(c, go(nav))
                else Column(Modifier.fillMaxSize()) { LicenseNotice(c, go(nav)); Box(Modifier.weight(1f)) { HomeScreen(c, go(nav)) } }
            }
            composable("licencia") { LicenseScreen(c) }
            composable("entrenamiento") { if (full) { TrainingScreen(c, go(nav)) } else LockedFeature(go(nav)) }
            composable("historial") { HistoryScreen(c, go(nav), incomingAvo, onImportHandled) }
            composable("caballos") { HorsesScreen(c, go(nav)) }
            composable("configuracion") { if (full) { SettingsScreen(c, go(nav)) } else LockedFeature(go(nav)) }
            composable("bluetooth") { if (full) { BluetoothScreen(c, requestPerms) } else LockedFeature(go(nav)) }
            composable("ntrip") { if (full) { NtripScreen(c) } else LockedFeature(go(nav)) }
            composable("nfc") { if (full) { NfcScreen(c) } else LockedFeature(go(nav)) }
            composable("mareas") { if (full) { TidesScreen(c) } else LockedFeature(go(nav)) }
            composable("geocercas") { if (full) { GeofencesScreen(c) } else LockedFeature(go(nav)) }
            composable("sincronizacion") { if (full) { SyncScreen(c) } else LockedFeature(go(nav)) }
            composable("diagnosticos") { if (full) { DiagnosticsScreen(c) } else LockedFeature(go(nav)) }
            composable("dispositivos") { if (full) { DeviceManagerScreen(c) } else LockedFeature(go(nav)) }
            composable("almacenamiento") { if (full) { StorageScreen(c) } else LockedFeature(go(nav)) }
            composable("jinetes") { if (full) { RidersScreen(c, go(nav)) } else LockedFeature(go(nav)) }
            composable("compartir") { if (full) { org.avoperformance.horse.ui.screens.ShareScreen(c) } else LockedFeature(go(nav)) }
            composable("lugar") { if (full) { org.avoperformance.horse.ui.screens.SpotScreen(c) } else LockedFeature(go(nav)) }
            composable("nomolestar") { if (full) { org.avoperformance.horse.ui.screens.DndScreen(c) } else LockedFeature(go(nav)) }
            composable("favoritos") { if (full) { org.avoperformance.horse.ui.screens.WhatsAppFavoritesScreen(c) } else LockedFeature(go(nav)) }
            composable("copias") { if (full) { org.avoperformance.horse.ui.screens.BackupScreen(c) } else LockedFeature(go(nav)) }
            composable("acerca") { org.avoperformance.horse.ui.screens.AboutScreen() }
            composable("caballo/{code}") { org.avoperformance.horse.ui.screens.HorseProfileScreen(c, it.arguments?.getString("code") ?: "", go(nav)) }
            composable("jinete/{code}") { org.avoperformance.horse.ui.screens.RiderProfileScreen(c, it.arguments?.getString("code") ?: "", go(nav)) }
            composable("comparar/{a}/{b}") { back -> CompareScreen(c, back.arguments?.getString("a") ?: "", back.arguments?.getString("b") ?: "") }
            composable("detalle/{id}") { TrainingDetailScreen(c, it.arguments?.getString("id") ?: "") }
        }
    }
}

private fun go(nav: NavHostController): (String) -> Unit = { nav.navigate(it) }
