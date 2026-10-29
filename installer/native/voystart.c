/* voystart.dll: starts the Voyager Access helper with no window.
 *
 * helperstart.lua starts the helper when none is running (Casey,
 * 2026-10-29: "the mod should start the helper whenever possible").
 * os.execute and io.popen both go through cmd.exe, whose console window
 * made NVDA say "C:\Windows\system32\cmd.exe" (VM, 2026-10-29), and Casey
 * asked for no command line windows. UE4SS's Lua has package.loadlib, so
 * this DLL gives it one function. It never touches Lua: the lua_State
 * argument is ignored and it returns 0 (no results), so no Lua headers or
 * symbols are needed. It starts
 *   %LOCALAPPDATA%\Programs\VoyagerAccess\VoyagerAccess.exe --attach
 * with CREATE_NO_WINDOW and does not wait for it.
 *
 * Built by installer\build.ps1 (cl.exe from the Visual Studio Build Tools).
 */
#include <windows.h>
#include <wchar.h>

__declspec(dllexport) int voy_start(void *L)
{
    wchar_t exe[1024];
    wchar_t cmd[1100];
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    DWORD n;

    (void)L;
    n = ExpandEnvironmentStringsW(L"%LOCALAPPDATA%\\Programs\\VoyagerAccess\\VoyagerAccess.exe",
                                  exe, (DWORD)(sizeof exe / sizeof exe[0]));
    if (n == 0 || n > sizeof exe / sizeof exe[0])
        return 0;
    if (GetFileAttributesW(exe) == INVALID_FILE_ATTRIBUTES)
        return 0;
    if (swprintf(cmd, sizeof cmd / sizeof cmd[0], L"\"%ls\" --attach", exe) < 0)
        return 0;
    ZeroMemory(&si, sizeof si);
    si.cb = sizeof si;
    ZeroMemory(&pi, sizeof pi);
    if (CreateProcessW(exe, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW | DETACHED_PROCESS,
                       NULL, NULL, &si, &pi)) {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
    return 0;
}
