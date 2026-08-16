R4OS Software Example
=====================

Dieses Projekt ist das grosse bestehende SDK-Beispiel fuer eine Desktop-
Anwendung mit dem SDK-eigenen App-Einstieg und der R4OS-GUI-Fassade.

Gezeigt wird:
- fachlicher Einstieg ueber `r4_app_main`; das SDK erzeugt R4XStart
- gruppierte API-Kontexte: R4SYS, R4DESK, R4DRAW, R4NET, R4AUDIO und R4DEV
- Console-Ausgabe
- Rohargumente aus der Shell
- einfacher Dateiexistenztest
- API-Uebersicht fuer Version, Tastaturlayout, Bildschirm, Netzstatus,
  Audiomodell und Device Inventory
- Rueckkehr zur Shell mit Exit-Code 0
- gehosteter GUI-Modus unter Desktop
- r4os.gui Canvas, Label, Button, TextField, Checkbox, RadioButton, GroupBox,
  Separator, Dropdown, List, Menu, MessageDialog und FileDialog
- grundlegende Maus-, Tastatur- und Dialog-Actions fuer diese Controls
- Fokusbedienung mit FocusState, MouseCapture, Tab, Shift+Tab, Enter, Escape,
  Space und Pfeiltasten
- typisierte Window-Nachrichten und wartender EventLoop ohne Drei-Tick-Polling
- genau ein `PaintContext.present()` pro gezeichnetem Frame

Build:

    cd Code\System\Software\Example
    ..\..\..\DevTools\Zig\zig.exe build

Eigenes Projektergebnis:

    Code\System\Software\Example\zig-out\EXAMPLE.R4X

Dev-Aggregate-Build:

    cd Code
    ..\DevTools\Zig\zig.exe build

Aggregate-Ergebnis:

    Code\zig-out\EXAMPLE.R4X

Im normalen Image liegt die Datei unter:

    C:\R4OS\SOFTWARE\DESKTOP\EXAMPLE.R4X

Aufruf in R4OS:

    C:\>EXAMPLE TEST 123

Im Desktop startet EXAMPLE als GUI-App und dient als sichtbare Demo fuer den
aktuellen `r4os.gui`-Werkzeugkasten. Der gehostete Pfad nutzt R4DESK fuer
Fensterstatus, Titel, Mindestgroesse und Events, R4DRAW fuer Canvas/Present
und R4SYS fuer Laufzeitsteuerung. Die zusaetzlichen GUI-Vertraege fuer
Controls, Layout, Dialoge, Fokus und Actions werden im Host-Test abgedeckt.
Die SDK-Fassade verbindet diesen Workflow, ohne R4DESK und R4DRAW im ABI
zusammenzulegen.

Projektstruktur seit 0.51.18:
- `build.zig` baut EXAMPLE.R4X als eigenes SDK-Projekt.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` beschreibt Artefakt, Zielpfad und Contract.
- R4L-Imports: `R4DESK:Query:1`, `R4DRAW:Query:1`, `R4NET:Query:1`,
  `R4AUDIO:Query:1`, `R4DEV:Query:1`.

Reine Geometrie-, Hit-Test-, Fokus- und Action-Vertraege werden ausserdem auf
dem Host geprueft mit:

    Tests\Gate\GuiSdkTests.bat
