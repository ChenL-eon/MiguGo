; MiguGo Windows installer (Inno Setup 6)
; Build: ISCC.exe /DAppVersion=1.1.0 windows\installer\MiguGo.iss
; ChineseSimplified.isl is the official translation from
; https://github.com/jrsoftware/issrc/tree/main/Files/Languages

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "MiguGo"
#define AppPublisher "ChenL-eon"
#define AppURL "https://github.com/ChenL-eon/MiguGo"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{A03B6290-194A-4969-BD5F-D75853C16E7B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
AppComments=个人学习项目，非咪咕官方软件
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename={#AppName}-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppName}.exe
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=no
VersionInfoCompany=cn.migulele
VersionInfoDescription={#AppName} 安装程序
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoCopyright=Copyright (C) 2026 cn.migulele
VersionInfoOriginalFileName={#AppName}-{#AppVersion}-windows-x64-setup.exe

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb"

[InstallDelete]
Type: filesandordirs; Name: "{app}\data"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppName}.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppName}.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppName}.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  WebView2Client = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

function HasWebView2Runtime(RootKey: Integer; const SubKey: string): Boolean;
var
  Version: string;
begin
  Result := False;
  if RegQueryStringValue(RootKey, SubKey, 'pv', Version) then
    Result := Version <> '';
end;

function IsWebView2RuntimeInstalled: Boolean;
begin
  Result :=
    HasWebView2Runtime(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\' + WebView2Client) or
    HasWebView2Runtime(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + WebView2Client) or
    HasWebView2Runtime(HKCU, 'Software\Microsoft\EdgeUpdate\Clients\' + WebView2Client);
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if (not IsWebView2RuntimeInstalled) and (not WizardSilent) then
    MsgBox('未检测到 Microsoft Edge WebView2 Runtime。' + #13#10 + #13#10 +
      'MiguGo 的官方登录窗口和内嵌播放器需要它。安装完成后，请先从 Microsoft 官网安装 WebView2 Runtime，再启动应用。',
      mbInformation, MB_OK);
end;
