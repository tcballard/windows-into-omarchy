; Optional redistribution build. The normal WindowsIntoOmarchy.iss installer
; direct-downloads the pinned upstream QEMU installer during preparation.
; Build runtime/qemu first with scripts/Build-Runtime.ps1 -Mode Bundle and an
; approved compliance manifest matching the locked QEMU build.
#define BundleQemuRuntime
#include "WindowsIntoOmarchy.iss"
