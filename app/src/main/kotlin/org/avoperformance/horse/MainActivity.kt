package org.avoperformance.horse

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.content.Intent
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
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
    private var incomingAvo by mutableStateOf<Uri?>(null)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingAvo = extractAvoUri(intent)
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
        if (!Perms.bluetoothGranted(this)) permLauncher.launch(Perms.required)
        setContent {
            AvoTheme {
                var bootVisible by rememberSaveable { mutableStateOf(savedInstanceState == null) }
                LaunchedEffect(Unit) { delay(3000L); bootVisible = false }
                if (bootVisible) AvoBootScreen(c, onContinue = { bootVisible = false })
                else AvoNav(c, incomingAvo, onImportHandled = { incomingAvo = null }) { permLauncher.launch(Perms.required) }
            }
        }
    }
}

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("inicio", "Inicio", Icons.Filled.Home),
    Tab("entrenamiento", "Entrenamiento", Icons.Filled.PlayArrow),
    Tab("historial", "Historial", Icons.AutoMirrored.Filled.List),
    Tab("caballos", "Caballos", Icons.Filled.Favorite),
    Tab("configuracion", "Configuración", Icons.Filled.Settings),
)

private val titles = mapOf(
    "bluetooth" to "Bluetooth", "ntrip" to "NTRIP", "geocercas" to "Geocercas", "sincronizacion" to "Sincronización",
    "diagnosticos" to "Diagnósticos", "dispositivos" to "Dispositivos y OTA", "almacenamiento" to "Almacenamiento", "jinetes" to "Jinetes", "detalle/{id}" to "Entrenamiento", "comparar/{a}/{b}" to "Comparativa",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AvoNav(c: AppContainer, incomingAvo: Uri? = null, onImportHandled: () -> Unit = {}, requestPerms: () -> Unit) {
    val nav = rememberNavController()
    LaunchedEffect(incomingAvo) { if (incomingAvo != null) nav.navigate("historial") { launchSingleTop = true } }
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val isTab = tabs.any { it.route == route }
    Scaffold(
        containerColor = AvoColors.Bg,
        topBar = {
            TopAppBar(
                title = { Text(tabs.firstOrNull { it.route == route }?.label ?: titles[route] ?: "AVO Performance Horse") },
                navigationIcon = { if (!isTab && route != null) IconButton(onClick = { nav.popBackStack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Atrás") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AvoColors.Bg, titleContentColor = AvoColors.Gold),
            )
        },
        bottomBar = {
            if (isTab) NavigationBar(containerColor = AvoColors.Surface) {
                tabs.forEach { t ->
                    NavigationBarItem(
                        selected = route == t.route,
                        onClick = { nav.navigate(t.route) { popUpTo("inicio") { saveState = true }; launchSingleTop = true; restoreState = true } },
                        icon = { Icon(t.icon, t.label) },
                        label = { Text(t.label, maxLines = 1) },
                        colors = NavigationBarItemDefaults.colors(selectedIconColor = AvoColors.Gold, selectedTextColor = AvoColors.Gold, indicatorColor = AvoColors.Surface2),
                    )
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
            composable("geocercas") { GeofencesScreen(c) }
            composable("sincronizacion") { SyncScreen(c) }
            composable("diagnosticos") { DiagnosticsScreen(c) }
            composable("dispositivos") { DeviceManagerScreen(c) }
            composable("almacenamiento") { StorageScreen(c) }
            composable("jinetes") { RidersScreen(c) }
            composable("comparar/{a}/{b}") { back -> CompareScreen(c, back.arguments?.getString("a") ?: "", back.arguments?.getString("b") ?: "") }
            composable("detalle/{id}") { TrainingDetailScreen(c, it.arguments?.getString("id") ?: "") }
        }
    }
}

private fun go(nav: NavHostController): (String) -> Unit = { nav.navigate(it) }
