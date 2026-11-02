# WinGet bootstrap (test before adding to the setup guide)

Open this page on the Windows machine. In **Windows PowerShell (Admin)**, run
this **one line**, then continue Phase 3 in that same window:

```powershell
iex (irm 'https://raw.githubusercontent.com/kamilomelo/kmos/win11/platforms/windows/install-winget-test.ps1')
```

Review the [script source](install-winget-test.ps1) before running this line:
it executes code fetched from GitHub. The script targets Windows 11 and the
Windows-supplied PowerShell 5.1. It attempts registration, then installs the
official stable App Installer package. If Windows reports that **Windows App
Runtime 1.8**, **VCLibs Desktop**, or **UI.Xaml 2.8** is missing, it asks once
for consent, installs the reported Microsoft prerequisite, and retries. It does not install
PowerShell Preview or a PowerShell Gallery module. This remains a **test**, not
a verified fleet deployment procedure.

Sources: [Microsoft WinGet guidance](https://learn.microsoft.com/en-us/windows/package-manager/winget/),
[stable App Installer download](https://github.com/microsoft/winget-cli/blob/master/doc/troubleshooting/README.md),
and [Microsoft framework instructions](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/deployment/install-winget-windows-iot).
The Windows App Runtime 1.8 installer comes from [Microsoft's supported stable 1.8 downloads](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads-archive#supported-stable-releases)
and its Microsoft signature is checked before it runs.
