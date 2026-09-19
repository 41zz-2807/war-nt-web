; ============================================================================
;  WarnetClientSetup.iss - Installer GUI agen client warnet (Inno Setup 6)
;
;  Hasil  : installer\dist\WarnetClientSetup.exe
;  Build  : pastikan dulu folder installer\Release ada (jalankan build-windows.ps1),
;           lalu:  ISCC.exe WarnetClientSetup.iss
;  CLI    : WarnetClientSetup.exe /ServerUrl="ws://..." /Token="abc123" /PCName="PC-01"
; ============================================================================

[Setup]
AppId={{B1A2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D}
AppName=Warnet Billing Client Agent
AppVersion=1.0.0
AppPublisher=Warnet Billing
DefaultDirName={autopf}\WarnetBillingClient
DefaultGroupName=Warnet Billing
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=WarnetClientSetup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
SetupLogging=yes
UninstallDisplayName=Warnet Billing Client Agent
CloseApplications=no

[Files]
Source: "..\Release\*";      DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "run-hidden.vbs";    DestDir: "{app}"; Flags: ignoreversion

[Registry]
; Hardening per user (dihapus otomatis saat uninstall via uninsdeletevalue)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Policies\System"; ValueType: dword; ValueName: "DisableTaskMgr";       ValueData: "1"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Policies";       ValueType: dword; ValueName: "NoRun";                       ValueData: "1"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Policies\System"; ValueType: dword; ValueName: "DisableRegistryTools";     ValueData: "1"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Policies\System"; ValueType: dword; ValueName: "DisableCMD";               ValueData: "1"; Flags: uninsdeletevalue

[Icons]
Name: "{autoprograms}\Konfigurasi Warnet Billing Client"; Filename: "notepad.exe"; Parameters: "{app}\client-net.dll.config"
Name: "{autodesktop}\Warnet Billing Client"; Filename: "{app}\run-hidden.vbs"; WorkingDir: "{app}"; Comment: "Jalankan agen client warnet"

[Code]
var
  ServerUrlPage: TInputQueryWizardPage;

procedure InitializeWizard;
begin
  ServerUrlPage := CreateInputQueryPage(
    wpWelcome, 'Konfigurasi Agen Client', 'Isi koneksi ke server warnet.',
    'Data ini ditulis ke client-net.dll.config di folder instalasi. ' +
    'Token didapat dari dashboard kasir (halaman PC Simulasi).');
  ServerUrlPage.Add('Server URL (ws://ip-server:3000/socket.io/):', False);
  ServerUrlPage.Add('Token PC:', False);
  ServerUrlPage.Add('Nama PC (opsional):', False);
  ServerUrlPage.Values[0] := 'ws://192.168.1.10:3000/socket.io/';
  ServerUrlPage.Values[1] := '';
  ServerUrlPage.Values[2] := GetComputerNameString;
end;

function Sanitize(const S: string): string;
var
  R: string;
begin
  R := S;
  StringChange(R, '&', '&amp;');
  StringChange(R, '"', '');
  StringChange(R, '<', '&lt;');
  StringChange(R, '>', '&gt;');
  Result := R;
end;

procedure CreateScheduledTask;
var
  ResultCode: Integer;
  VbsPath: string;
begin
  VbsPath := ExpandConstant('{app}\run-hidden.vbs');
  Exec('schtasks',
       '/Create /F /TN "WarnetBillingClient" /SC ONLOGON /RL LIMITED /TR "' + VbsPath + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if ResultCode <> 0 then
    MsgBox('Gagal membuat Scheduled Task (kode ' + IntToStr(ResultCode) +
           '). Agen tetap bisa dijalankan manual.', mbInformation, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  FilePath: string;
  i: Integer;
  tokens: TStringList;
begin
  if CurStep = ssPostInstall then
  begin
    // ---- tulis client-net.dll.config dari input wizard ----
    FilePath := ExpandConstant('{app}\client-net.dll.config');
    tokens := TStringList.Create;
    try
      tokens.Add('<?xml version="1.0" encoding="utf-8" ?>');
      tokens.Add('<configuration>');
      tokens.Add('  <startup>');
      tokens.Add('    <supportedRuntime version="v8.0" sku=".NETFramework,Version=v8.0" />');
      tokens.Add('  </startup>');
      tokens.Add('  <appSettings>');
      tokens.Add('    <add key="ServerUrl" value="' + Sanitize(ServerUrlPage.Values[0]) + '" />');
      tokens.Add('    <add key="PcId" value="' + Sanitize(ServerUrlPage.Values[2]) + '" />');
      tokens.Add('    <add key="Token" value="' + Sanitize(ServerUrlPage.Values[1]) + '" />');
      tokens.Add('    <add key="HeartbeatInterval" value="20" />');
      tokens.Add('    <add key="IdleTimeoutMinutes" value="5" />');
      tokens.Add('  </appSettings>');
      tokens.Add('</configuration>');
      tokens.SaveToFile(FilePath, TEncoding.UTF8);
    finally
      tokens.Free;
    end;

    // ---- daftarkan Scheduled Task saat login ----
    CreateScheduledTask;

    // ---- jalankan agen sekarang (via vbs agar hidden + hardening ulang) ----
    Exec(ExpandConstant('{app}\run-hidden.vbs'), '', '', SW_HIDE, ewNoWait, i);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    // hentikan proses agen
    Exec('taskkill', '/F /IM client-net.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    // hapus Scheduled Task
    Exec('schtasks', '/Delete /F /TN "WarnetBillingClient"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;