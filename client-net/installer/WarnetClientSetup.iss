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

{ ============================================================================
  OTP-UNINSTALL via Telegram:
  Saat uninstaller dibuka, script meminta OTP ke server (server mengirim kode
  ke Telegram admin). User memasukkan kode -> diverifikasi server -> baru
  uninstall dilanjutkan. Bila server tidak terjangkau / Telegram nonaktif,
  uninstall tetap boleh lanjut (mode dev).
  ============================================================================ }

var
  OtpPage: TInputQueryWizardPage;
  OtpServerApi: string;
  OtpPcName: string;
  OtpUsed: Boolean;

function HttpPost(Method, Url, JsonBody: string; out RespBody: string): Integer;
var
  h: Variant;
begin
  RespBody := '';
  try
    h := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    h.Open(Method, Url, False);
    h.SetTimeouts(10000, 10000, 10000, 10000);
    h.SetRequestHeader('Content-Type', 'application/json');
    if JsonBody = '' then h.Send else h.Send(JsonBody);
    Result := h.Status;
    RespBody := h.ResponseText;
  except
    Result := -1;
  end;
end;

function JsonField(const S, Field: string; out Value: string): Boolean;
var
  Key, Tail: string;
  P, LenFull, EndPos: Integer;
begin
  Key := '"' + Field + '"';
  P := Pos(Key, S);
  Result := P > 0;
  if not Result then Exit;
  Tail := Copy(S, P + Length(Key), MaxInt);
  P := 1;
  while (P <= Length(Tail)) and (Tail[P] in [' ', ':']) do Inc(P);
  LenFull := Length(Tail);
  if P > LenFull then Exit;
  if Tail[P] = '"' then
  begin
    Inc(P);
    EndPos := PosEx('"', Tail, P);
    if EndPos = 0 then Exit;
    Value := Copy(Tail, P, EndPos - P);
  end
  else
  begin
    EndPos := PosEx(',', Tail, P);
    if EndPos = 0 then EndPos := LenFull;
    Value := Trim(Copy(Tail, P, EndPos - P));
  end;
end;

procedure LoadOtpConfig;
var
  F: TStringList;
  i, p, e: Integer;
  line, key, val: string;
begin
  OtpServerApi := '';
  OtpPcName := GetComputerNameString;
  F := TStringList.Create;
  try
    if not FileExists(ExpandConstant('{app}\client-net.dll.config')) then Exit;
    F.LoadFromFile(ExpandConstant('{app}\client-net.dll.config'));
    for i := 0 to F.Count - 1 do
    begin
      line := F[i];
      p := Pos('key="', line);
      if p = 0 then Continue;
      key := Copy(line, p + 5, MaxInt);
      e := Pos('"', key);
      key := Copy(key, 1, e - 1);
      p := Pos('value="', line);
      if p = 0 then Continue;
      val := Copy(line, p + 7, MaxInt);
      e := Pos('"', val);
      val := Copy(val, 1, e - 1);
      if key = 'ServerUrl' then
      begin
        // ws://host:port/... -> http://host:port
        StringChange(val, 'ws://', 'http://');
        StringChange(val, 'wss://', 'https://');
        // buang suffix /socket.io/
        p := Pos('/socket.io', val);
        if p > 0 then val := Copy(val, 1, p - 1);
        OtpServerApi := val;
      end
      else if key = 'PcId' then
        OtpPcName := val;
    end;
  finally
    F.Free;
  end;
end;

procedure InitializeUninstallWizard;
var
  resp, st: string;
begin
  OtpUsed := False;
  LoadOtpConfig;
  if OtpServerApi = '' then Exit; // tanpa config -> lanjut tanpa OTP
  if HttpPost('GET', OtpServerApi + '/api/otp/status', '', resp) = -1 then
    OtpUsed := True // server tak terjangkau -> lewati
  else if JsonField(resp, 'enabled', st) and (st <> 'true') and (st <> 'True') then
    OtpUsed := True // Telegram nonaktif -> mode dev, lewati
  else
  begin
    OtpPage := CreateInputQueryPage(wpWelcome,
      'Verifikasi OTP (Uninstall)',
      'Masukkan kode OTP dari Telegram admin.',
      'Kode OTP telah dikirim ke Telegram admin/operator warnet. ' +
      'Tanpa kode yang valid, uninstall akan dibatalkan.');
    OtpPage.Add('Kode OTP (6 digit):', False);
    OtpPage.Values[0] := '';
    // kirim permintaan OTP sekarang (memicu notifikasi Telegram)
    HttpPost('POST', OtpServerApi + '/api/otp/request',
             '{"pc_name":"' + OtpPcName + '","purpose":"uninstall"}', resp);
  end;
end;

function VerifyOtp(const Otp: string): Boolean;
var
  resp, okField: string;
begin
  Result := False;
  if OtpServerApi = '' then Exit;
  if HttpPost('POST', OtpServerApi + '/api/otp/verify',
              '{"pc_name":"' + OtpPcName + '","purpose":"uninstall","code":"' + Otp + '"}', resp) = -1 then Exit;
  if JsonField(resp, 'ok', okField) then
    Result := (okField = 'true') or (okField = 'True');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (OtpPage <> nil) and (CurPageID = OtpPage.ID) and (not OtpUsed) then
  begin
    if Trim(OtpPage.Values[0]) = '' then
    begin
      MsgBox('Masukkan kode OTP.', mbError, MB_OK);
      Result := False;
    end
    else if not VerifyOtp(Trim(OtpPage.Values[0])) then
    begin
      MsgBox('Kode OTP salah atau server tidak terjangkau. Coba lagi, atau ' +
             'minta kode baru ke admin.', mbError, MB_OK);
      Result := False;
    end
    else
      OtpUsed := True;
  end;
end;