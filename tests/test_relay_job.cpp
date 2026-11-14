// Windows-only test: starts a copy of itself, not Java or the game.
#include "../relay/job_process.h"

#include <cassert>
#include <string>

int wmain(int argc, wchar_t **argv)
{
	if (argc == 2 && std::wstring(argv[1]) == L"--child")
	{
		Sleep(60000);
		return 0;
	}

	wchar_t path[32768]{};
	const DWORD length = GetModuleFileNameW(nullptr, path, 32768);
	assert(length > 0 && length < 32768);
	const std::wstring command = L"\"" + std::wstring(path) + L"\" --child";
	HANDLE observed = nullptr;
	{
		w3coop::JobProcess server;
		// An executable file is not a valid working directory.
		assert(server.Start(command, path) == nullptr);
		const HANDLE process = server.Start(command, nullptr);
		assert(process != nullptr);
		assert(WaitForSingleObject(process, 0) == WAIT_TIMEOUT);
		assert(DuplicateHandle(GetCurrentProcess(), process, GetCurrentProcess(), &observed,
		                       0, FALSE, DUPLICATE_SAME_ACCESS));
	}
	// Closing the owning job must terminate the running child.
	const DWORD result = WaitForSingleObject(observed, 5000);
	if (result != WAIT_OBJECT_0)
		TerminateProcess(observed, 1);
	CloseHandle(observed);
	assert(result == WAIT_OBJECT_0);
}
