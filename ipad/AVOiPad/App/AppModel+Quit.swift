import Foundation
import UIKit

// Botón «SALIR» de la barra lateral (boceto del entrenador, 15/11/2026: «botón para cerrar completamente app»).
// iPadOS no tiene una forma oficial de cerrar una app: se cierra todo lo que la app tiene abierto (Wi-Fi y Bluetooth
// del reloj, cámara), se guarda el registro, se manda la app al fondo como el gesto de inicio y se termina el proceso.
// Apple desaconseja cerrar la app por código; en TestFlight funciona, pero en la App Store la revisión podría pedir
// quitarlo.
extension AppModel {
    func quitApp() {
        log.info("app", "Salir: cierre completo pedido por el usuario")
        let wasRecording = camera?.recording == true      // el vídeo necesita un momento para cerrarse en disco
        watchWifi?.disconnect()
        camera?.pageHidden()
        UserDefaults.standard.synchronize()
        // a la pantalla de inicio (como deslizar hacia arriba) y, ya en segundo plano, fin del proceso
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasRecording ? 2.5 : 0.6)) { exit(0) }
    }
}
