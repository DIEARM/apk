@echo off
cd /d C:\Android\cmdline-tools\latest\bin
(
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
) | sdkmanager.bat --sdk_root=C:\Android --licenses
