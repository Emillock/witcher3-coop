// w3test.asi: support for automated test runs.
// - Script natives (environment access, per-instance log, quit), registered through WitcherNativeBridge.
// - Only when W3T_SCENARIO is set: in-process hooks so several instances run unattended next to the owner's
//   work: per-instance mutex names, no pause or input capture when unfocused, message boxes logged and
//   dismissed, the process's audio session muted (W3T_MUTE=0 keeps sound), and "Documents" redirected to
//   W3T_DOCUMENTS so settings, saves and logs live in a per-test sandbox, never in the owner's folder.
#include <windows.h>

#include <audiopolicy.h>
#include <knownfolders.h>
#include <mmdeviceapi.h>
#include <shlobj.h>

#include <WitcherNativeBridgeApi.h>

#include <atomic>
#include <climits>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")

namespace
{
	std::mutex g_logMutex;
	FILE *g_log = nullptr;
	std::atomic<HWND> g_gameWindow{nullptr};
	WNDPROC g_originalWndProc = nullptr;

	std::wstring GetEnv(const wchar_t *name)
	{
		wchar_t buffer[4096];
		const DWORD n = GetEnvironmentVariableW(name, buffer, 4096);
		return (n > 0 && n < 4096) ? std::wstring(buffer, n) : std::wstring();
	}

	bool TestMode()
	{
		static const bool enabled = !GetEnv(L"W3T_SCENARIO").empty();
		return enabled;
	}

	std::string ToUtf8(const std::wstring &text)
	{
		if (text.empty())
			return {};
		const int bytes = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
		std::string out(static_cast<size_t>(bytes), '\0');
		WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), bytes, nullptr, nullptr);
		return out;
	}

	void WriteLog(const std::string &line)
	{
		std::lock_guard<std::mutex> lock(g_logMutex);
		if (!g_log)
		{
			std::wstring path = GetEnv(L"W3T_LOG");
			if (path.empty())
				path = L"w3test_" + std::to_wstring(GetCurrentProcessId()) + L".log";
			g_log = _wfsopen(path.c_str(), L"a", _SH_DENYNO);
			if (!g_log)
				return;
		}

		SYSTEMTIME now{};
		GetLocalTime(&now);
		fprintf(g_log, "%02u:%02u:%02u.%03u %s\n", now.wHour, now.wMinute, now.wSecond, now.wMilliseconds, line.c_str());
		fflush(g_log);
	}

	// ---- in-process hooks (test mode only) ----

	bool IsReallyForeground()
	{
		const HWND game = g_gameWindow.load();
		return game && GetForegroundWindow() == game;
	}

	using CreateMutexWFn = HANDLE(WINAPI *)(LPSECURITY_ATTRIBUTES, BOOL, LPCWSTR);
	using CreateMutexAFn = HANDLE(WINAPI *)(LPSECURITY_ATTRIBUTES, BOOL, LPCSTR);
	CreateMutexWFn g_createMutexW = nullptr;
	CreateMutexAFn g_createMutexA = nullptr;

	HANDLE WINAPI HookCreateMutexW(LPSECURITY_ATTRIBUTES attributes, BOOL initialOwner, LPCWSTR name)
	{
		if (!name)
			return g_createMutexW(attributes, initialOwner, name);

		const std::wstring unique = std::wstring(name) + L"_w3t" + std::to_wstring(GetCurrentProcessId());
		WriteLog("HOOK CreateMutexW '" + ToUtf8(name) + "' -> per-instance name");
		return g_createMutexW(attributes, initialOwner, unique.c_str());
	}

	HANDLE WINAPI HookCreateMutexA(LPSECURITY_ATTRIBUTES attributes, BOOL initialOwner, LPCSTR name)
	{
		if (!name)
			return g_createMutexA(attributes, initialOwner, name);

		const std::string unique = std::string(name) + "_w3t" + std::to_string(GetCurrentProcessId());
		WriteLog(std::string("HOOK CreateMutexA '") + name + "' -> per-instance name");
		return g_createMutexA(attributes, initialOwner, unique.c_str());
	}

	using GetForegroundWindowFn = HWND(WINAPI *)();
	GetForegroundWindowFn g_getForegroundWindow = nullptr;

	HWND WINAPI HookGetForegroundWindow()
	{
		const HWND game = g_gameWindow.load();
		return game ? game : g_getForegroundWindow();
	}

	using ClipCursorFn = BOOL(WINAPI *)(const RECT *);
	ClipCursorFn g_clipCursor = nullptr;

	BOOL WINAPI HookClipCursor(const RECT *)
	{
		// never trap the owner's mouse in a test window
		g_clipCursor(nullptr);
		return TRUE;
	}

	using SetCursorPosFn = BOOL(WINAPI *)(int, int);
	SetCursorPosFn g_setCursorPos = nullptr;

	BOOL WINAPI HookSetCursorPos(int x, int y)
	{
		return IsReallyForeground() ? g_setCursorPos(x, y) : TRUE;
	}

	using SetForegroundWindowFn = BOOL(WINAPI *)(HWND);
	SetForegroundWindowFn g_setForegroundWindow = nullptr;

	BOOL WINAPI HookSetForegroundWindow(HWND)
	{
		return TRUE;
	}

	using GetAsyncKeyStateFn = SHORT(WINAPI *)(int);
	GetAsyncKeyStateFn g_getAsyncKeyState = nullptr;

	SHORT WINAPI HookGetAsyncKeyState(int key)
	{
		return IsReallyForeground() ? g_getAsyncKeyState(key) : 0;
	}

	using RegisterRawInputDevicesFn = BOOL(WINAPI *)(PCRAWINPUTDEVICE, UINT, UINT);
	RegisterRawInputDevicesFn g_registerRawInputDevices = nullptr;

	BOOL WINAPI HookRegisterRawInputDevices(PCRAWINPUTDEVICE devices, UINT count, UINT size)
	{
		RAWINPUTDEVICE copy[16];
		if (!devices || count == 0 || count > 16 || size != sizeof(RAWINPUTDEVICE))
			return g_registerRawInputDevices(devices, count, size);

		// background (INPUTSINK) delivery would feed the owner's typing into test instances
		for (UINT i = 0; i < count; ++i)
		{
			copy[i] = devices[i];
			copy[i].dwFlags &= ~(RIDEV_INPUTSINK | RIDEV_EXINPUTSINK);
		}
		return g_registerRawInputDevices(copy, count, size);
	}

	const std::wstring &SandboxDocuments()
	{
		static const std::wstring path = GetEnv(L"W3T_DOCUMENTS");
		return path;
	}

	using SHGetKnownFolderPathFn = HRESULT(WINAPI *)(REFKNOWNFOLDERID, DWORD, HANDLE, PWSTR *);
	using SHGetFolderPathWFn = HRESULT(WINAPI *)(HWND, int, HANDLE, DWORD, LPWSTR);
	using SHGetFolderPathAFn = HRESULT(WINAPI *)(HWND, int, HANDLE, DWORD, LPSTR);
	SHGetKnownFolderPathFn g_shGetKnownFolderPath = nullptr;
	SHGetFolderPathWFn g_shGetFolderPathW = nullptr;
	SHGetFolderPathAFn g_shGetFolderPathA = nullptr;

	HRESULT WINAPI HookSHGetKnownFolderPath(REFKNOWNFOLDERID id, DWORD flags, HANDLE token, PWSTR *path)
	{
		const std::wstring &sandbox = SandboxDocuments();
		if (sandbox.empty() || !IsEqualGUID(id, FOLDERID_Documents) || !path)
			return g_shGetKnownFolderPath(id, flags, token, path);

		const size_t bytes = (sandbox.size() + 1) * sizeof(wchar_t);
		*path = static_cast<PWSTR>(CoTaskMemAlloc(bytes));
		if (!*path)
			return E_OUTOFMEMORY;
		memcpy(*path, sandbox.c_str(), bytes);
		return S_OK;
	}

	HRESULT WINAPI HookSHGetFolderPathW(HWND owner, int folder, HANDLE token, DWORD flags, LPWSTR path)
	{
		const std::wstring &sandbox = SandboxDocuments();
		if (sandbox.empty() || (folder & 0xFF) != CSIDL_PERSONAL || !path || sandbox.size() >= MAX_PATH)
			return g_shGetFolderPathW(owner, folder, token, flags, path);

		wcscpy_s(path, MAX_PATH, sandbox.c_str());
		return S_OK;
	}

	HRESULT WINAPI HookSHGetFolderPathA(HWND owner, int folder, HANDLE token, DWORD flags, LPSTR path)
	{
		const std::wstring &sandbox = SandboxDocuments();
		if (sandbox.empty() || (folder & 0xFF) != CSIDL_PERSONAL || !path)
			return g_shGetFolderPathA(owner, folder, token, flags, path);

		if (!WideCharToMultiByte(CP_ACP, 0, sandbox.c_str(), -1, path, MAX_PATH, nullptr, nullptr))
			return E_FAIL;
		return S_OK;
	}

	using MessageBoxWFn = int(WINAPI *)(HWND, LPCWSTR, LPCWSTR, UINT);
	using MessageBoxAFn = int(WINAPI *)(HWND, LPCSTR, LPCSTR, UINT);
	MessageBoxWFn g_messageBoxW = nullptr;
	MessageBoxAFn g_messageBoxA = nullptr;

	int WINAPI HookMessageBoxW(HWND, LPCWSTR text, LPCWSTR caption, UINT)
	{
		WriteLog("MESSAGEBOX '" + ToUtf8(caption ? caption : L"") + "': " + ToUtf8(text ? text : L""));
		return IDOK;
	}

	int WINAPI HookMessageBoxA(HWND, LPCSTR text, LPCSTR caption, UINT)
	{
		WriteLog(std::string("MESSAGEBOX '") + (caption ? caption : "") + "': " + (text ? text : ""));
		return IDOK;
	}

	LRESULT CALLBACK GameWndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
	{
		switch (message)
		{
		case WM_ACTIVATEAPP:
			wParam = TRUE;
			break;
		case WM_ACTIVATE:
			if (LOWORD(wParam) == WA_INACTIVE)
				wParam = MAKEWPARAM(WA_ACTIVE, HIWORD(wParam));
			break;
		case WM_KILLFOCUS:
			return 0;
		}
		return CallWindowProcW(g_originalWndProc, hwnd, message, wParam, lParam);
	}

	bool PatchImport(HMODULE module, const char *dll, const char *function, void *hook, void **original)
	{
		auto *base = reinterpret_cast<uint8_t *>(module);
		const auto *dos = reinterpret_cast<IMAGE_DOS_HEADER *>(base);
		const auto *nt = reinterpret_cast<IMAGE_NT_HEADERS *>(base + dos->e_lfanew);
		const IMAGE_DATA_DIRECTORY &dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
		if (!dir.VirtualAddress)
			return false;

		for (auto *desc = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR *>(base + dir.VirtualAddress); desc->Name; ++desc)
		{
			if (_stricmp(reinterpret_cast<char *>(base + desc->Name), dll) != 0)
				continue;

			auto *names = reinterpret_cast<IMAGE_THUNK_DATA *>(base + (desc->OriginalFirstThunk ? desc->OriginalFirstThunk : desc->FirstThunk));
			auto *slots = reinterpret_cast<IMAGE_THUNK_DATA *>(base + desc->FirstThunk);
			for (; names->u1.AddressOfData; ++names, ++slots)
			{
				if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal))
					continue;
				const auto *byName = reinterpret_cast<IMAGE_IMPORT_BY_NAME *>(base + names->u1.AddressOfData);
				if (strcmp(byName->Name, function) != 0)
					continue;

				DWORD protection = 0;
				VirtualProtect(&slots->u1.Function, sizeof(void *), PAGE_READWRITE, &protection);
				*original = reinterpret_cast<void *>(slots->u1.Function);
				slots->u1.Function = reinterpret_cast<ULONG_PTR>(hook);
				VirtualProtect(&slots->u1.Function, sizeof(void *), protection, &protection);
				return true;
			}
		}
		return false;
	}

	template <typename Fn>
	void Hook(const char *dll, const char *function, Fn hook, Fn &original)
	{
		void *previous = nullptr;
		const bool ok = PatchImport(GetModuleHandleW(nullptr), dll, function, reinterpret_cast<void *>(hook), &previous);
		original = reinterpret_cast<Fn>(previous);
		WriteLog(std::string("HOOK ") + function + (ok ? " installed" : " NOT FOUND"));
	}

	void InstallHooks()
	{
		Hook("KERNEL32.dll", "CreateMutexW", &HookCreateMutexW, g_createMutexW);
		Hook("KERNEL32.dll", "CreateMutexA", &HookCreateMutexA, g_createMutexA);
		Hook("USER32.dll", "GetForegroundWindow", &HookGetForegroundWindow, g_getForegroundWindow);
		Hook("USER32.dll", "ClipCursor", &HookClipCursor, g_clipCursor);
		Hook("USER32.dll", "SetCursorPos", &HookSetCursorPos, g_setCursorPos);
		Hook("USER32.dll", "SetForegroundWindow", &HookSetForegroundWindow, g_setForegroundWindow);
		Hook("USER32.dll", "GetAsyncKeyState", &HookGetAsyncKeyState, g_getAsyncKeyState);
		Hook("USER32.dll", "RegisterRawInputDevices", &HookRegisterRawInputDevices, g_registerRawInputDevices);
		Hook("USER32.dll", "MessageBoxW", &HookMessageBoxW, g_messageBoxW);
		Hook("USER32.dll", "MessageBoxA", &HookMessageBoxA, g_messageBoxA);

		if (!SandboxDocuments().empty())
		{
			Hook("SHELL32.dll", "SHGetKnownFolderPath", &HookSHGetKnownFolderPath, g_shGetKnownFolderPath);
			Hook("SHELL32.dll", "SHGetFolderPathW", &HookSHGetFolderPathW, g_shGetFolderPathW);
			Hook("SHELL32.dll", "SHGetFolderPathA", &HookSHGetFolderPathA, g_shGetFolderPathA);
			WriteLog("SANDBOX Documents -> " + ToUtf8(SandboxDocuments()));
		}
		else
		{
			// never let a test instance read or write the owner's settings and saves
			WriteLog("SANDBOX missing (W3T_DOCUMENTS empty): refusing to run a test instance");
			TerminateProcess(GetCurrentProcess(), 9);
		}
	}

	BOOL CALLBACK FindGameWindow(HWND hwnd, LPARAM result)
	{
		DWORD pid = 0;
		GetWindowThreadProcessId(hwnd, &pid);
		wchar_t cls[64]{};
		GetClassNameW(hwnd, cls, 64);
		if (pid == GetCurrentProcessId() && wcscmp(cls, L"W2ViewportClass") == 0)
		{
			*reinterpret_cast<HWND *>(result) = hwnd;
			return FALSE;
		}
		return TRUE;
	}

	void MuteOwnAudioSessions(bool &announced)
	{
		IMMDeviceEnumerator *enumerator = nullptr;
		if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator))))
			return;

		IMMDevice *device = nullptr;
		IAudioSessionManager2 *manager = nullptr;
		IAudioSessionEnumerator *sessions = nullptr;
		if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device)) &&
		    SUCCEEDED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(&manager))) &&
		    SUCCEEDED(manager->GetSessionEnumerator(&sessions)))
		{
			int count = 0;
			sessions->GetCount(&count);
			for (int i = 0; i < count; ++i)
			{
				IAudioSessionControl *control = nullptr;
				IAudioSessionControl2 *control2 = nullptr;
				ISimpleAudioVolume *volume = nullptr;
				DWORD pid = 0;
				if (SUCCEEDED(sessions->GetSession(i, &control)) &&
				    SUCCEEDED(control->QueryInterface(IID_PPV_ARGS(&control2))) &&
				    SUCCEEDED(control2->GetProcessId(&pid)) && pid == GetCurrentProcessId() &&
				    SUCCEEDED(control->QueryInterface(IID_PPV_ARGS(&volume))))
				{
					BOOL muted = FALSE;
					volume->GetMute(&muted);
					if (!muted)
					{
						volume->SetMute(TRUE, nullptr);
						if (!announced)
						{
							WriteLog("AUDIO muted this process's audio session");
							announced = true;
						}
					}
				}
				if (volume)
					volume->Release();
				if (control2)
					control2->Release();
				if (control)
					control->Release();
			}
		}
		if (sessions)
			sessions->Release();
		if (manager)
			manager->Release();
		if (device)
			device->Release();
		enumerator->Release();
	}

	DWORD WINAPI WatchThread(LPVOID)
	{
		const bool mute = GetEnv(L"W3T_MUTE") != L"0";
		bool announced = false;
		CoInitializeEx(nullptr, COINIT_MULTITHREADED);

		for (;;)
		{
			if (!g_gameWindow.load())
			{
				HWND hwnd = nullptr;
				EnumWindows(&FindGameWindow, reinterpret_cast<LPARAM>(&hwnd));
				if (hwnd)
				{
					g_originalWndProc = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(hwnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&GameWndProc)));
					g_gameWindow.store(hwnd);
					WriteLog("WINDOW game window found; focus loss is ignored from now on");
				}
			}

			if (mute)
				MuteOwnAudioSessions(announced);

			Sleep(500);
		}
	}

	// ---- script natives ----

	std::wstring ReadWideString(void *frame)
	{
		WNB_String input{};
		if (WNB_ReadStringParameter(frame, &input) <= 0 || !input.data || input.size <= 1 || input.size > INT_MAX)
			return {};

		// Remastered script strings are UTF-8 bytes (the header still types them as wchar_t).
		const char *utf8 = reinterpret_cast<const char *>(input.data);
		const int bytes = static_cast<int>(input.size - 1);
		const int chars = MultiByteToWideChar(CP_UTF8, 0, utf8, bytes, nullptr, 0);
		if (chars <= 0)
			return {};

		std::wstring value(static_cast<size_t>(chars), L'\0');
		MultiByteToWideChar(CP_UTF8, 0, utf8, bytes, value.data(), chars);
		return value;
	}

	// import function W3T_GetEnv(name : string) : string;
	void W3T_GetEnv(void *, void *frame, void *result)
	{
		const std::wstring name = ReadWideString(frame);
		const std::wstring value = name.empty() ? std::wstring() : GetEnv(name.c_str());
		WNB_ReturnString(frame, result, value.c_str(), static_cast<uint32_t>(value.size()));
	}

	// import function W3T_Log(line : string);
	void W3T_Log(void *, void *frame, void *)
	{
		const std::wstring line = ReadWideString(frame);
		WNB_ReturnVoid(frame);
		WriteLog(ToUtf8(line));
	}

	// import function W3T_TimeMs() : int;
	void W3T_TimeMs(void *, void *frame, void *result)
	{
		WNB_ReturnInt(frame, result, static_cast<int>(GetTickCount64() & 0x7FFFFFFF));
	}

	// import function W3T_Quit(code : int);
	void W3T_Quit(void *, void *frame, void *)
	{
		const int code = WNB_ReadIntParameter(frame);
		WNB_ReturnVoid(frame);
		WriteLog("QUIT " + std::to_string(code));
		TerminateProcess(GetCurrentProcess(), static_cast<UINT>(code));
	}

	void Register()
	{
		const struct
		{
			const char *name;
			WNB_NativeImplementation implementation;
		} natives[] = {{"W3T_GetEnv", &W3T_GetEnv}, {"W3T_Log", &W3T_Log}, {"W3T_TimeMs", &W3T_TimeMs}, {"W3T_Quit", &W3T_Quit}};

		for (const auto &native : natives)
		{
			if (!WNB_RegisterNative(native.name, native.implementation))
				WriteLog(std::string("failed to register ") + native.name);
		}
	}
} // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
	if (reason == DLL_PROCESS_ATTACH)
	{
		DisableThreadLibraryCalls(module);
		Register();
		if (TestMode())
		{
			WriteLog("w3test loaded in test mode, pid " + std::to_string(GetCurrentProcessId()));
			InstallHooks();
			HANDLE thread = CreateThread(nullptr, 0, &WatchThread, nullptr, 0, nullptr);
			if (thread)
				CloseHandle(thread);
		}
	}
	return TRUE;
}
