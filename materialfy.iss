; Inno Setup script для Materialfy (Rust + Qt 6)
; Собирается из build_windows.ps1:
;   ISCC /DAppVersion=0.1.0 /DDistDir=target\dist\materialfy /Otarget\dist materialfy.iss
; Результат: target\dist\Materialfy-<версия>-Setup.exe
; Установка пользовательская (без UAC) — в %LocalAppData%\Programs\Materialfy

#define AppName "Materialfy"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
; числовая версия для свойств файла (без -rc1 и т. п.)
#ifndef AppNumVersion
  #define AppNumVersion AppVersion
#endif
; папка, собранная build_windows.ps1: materialfy.exe, qml\, assets\, Qt, рантайм MSVC
#ifndef DistDir
  #define DistDir "target\dist\materialfy"
#endif
#define AppPublisher "Materialfy"
#define AppExeName "materialfy.exe"

[Setup]
; AppId не менять: по нему новая версия ставится поверх старой. С YaMusic (yamusic-md3) не пересекается.
AppId={{A5260B19-41AE-4D9D-9841-204E686F2ADD}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppNumVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} — клиент Spotify в стиле Material 3 Expressive
; Пользовательская установка — не нужен UAC
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputDir=target\dist
OutputBaseFilename=Materialfy-{#AppVersion}-Setup
SetupIconFile=materialfy.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; Сборка только x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Без прав администратора
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Закрываем уже запущенный Materialfy перед обновлением
CloseApplications=yes
CloseApplicationsFilter=*{#AppExeName}
; Минимальная версия Windows — 10 1809
MinVersion=10.0.17763

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать значок на &рабочем столе";          GroupDescription: "Дополнительные значки:"; Flags: checkedonce
Name: "startupicon"; Description: "Запускать {#AppName} при старте Windows"; GroupDescription: "Автозапуск:";           Flags: unchecked

[InstallDelete]
; QML пересобирается целиком — убираем удалённые из новой версии файлы
Type: filesandordirs; Name: "{app}\qml"

[Files]
; Всё содержимое папки дистрибутива → папка установки
Source: "{#DistDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Меню «Пуск»
Name: "{userprograms}\{#AppName}\{#AppName}";         Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"; AppUserModelID: "{#AppName}"
Name: "{userprograms}\{#AppName}\Удалить {#AppName}"; Filename: "{uninstallexe}"

; Рабочий стол
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"; AppUserModelID: "{#AppName}"; Tasks: desktopicon

; Автозапуск
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: startupicon

[Run]
; Предложить запустить Materialfy после установки
Filename: "{app}\{#AppExeName}"; Description: "Запустить {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Настройки, вход (хранилище учётных данных Windows) и кэш при удалении остаются — их чистит «Выйти» в программе
