# Compilare il connettore senza un Mac

Il pacchetto `dist/matisse-ios-connector-cloud-build.zip` contiene solo il
workflow, il progetto Swift PhotoKit e il server bridge. Non contiene backup,
foto del telefono, report REA o credenziali.

1. Crea su GitHub un repository privato vuoto.
2. Estrai lo ZIP in una cartella sul PC e apri PowerShell in quella cartella.
3. Inizializza Git e collega il repository privato:

   ```powershell
   git init -b main
   git add .
   git commit -m "Prepare Matisse iOS connector build"
   git remote add origin <URL-del-repository-privato>
   git push -u origin main
   ```

4. Nel repository apri Actions, scegli "Build iOS connector" e avvia il workflow.
5. Scarica l'artifact `MatisseConnector-unsigned-ipa` e firmalo/installalo sul
   PC Windows con un programma di sideloading compatibile.

La firma gratuita Apple scade periodicamente e va rinnovata. Per app di sviluppo
su iOS 16, Apple richiede [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
Come strumento Windows puoi valutare [Sideloadly](https://sideloadly.io/), che
dichiara la firma con Apple ID gratuito e il rinnovo automatico. Inserisci le
credenziali Apple soltanto nel programma di firma sul tuo PC; non inserirle nel
repository né inviarle in chat.

Il workflow produce un IPA non firmato. Il connettore PhotoKit non e ancora stato
compilato o installato su questo iPhone; la prova sul telefono resta necessaria.
