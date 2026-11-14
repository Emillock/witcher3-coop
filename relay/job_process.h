#pragma once

#include <windows.h>

#include <cstdio>
#include <string>

namespace w3coop
{
	// The job must own the server before its first instruction runs.
	class JobProcess
	{
		HANDLE job = nullptr;
		HANDLE process = nullptr;

	public:
		JobProcess() = default;
		JobProcess(const JobProcess &) = delete;
		JobProcess &operator=(const JobProcess &) = delete;

		~JobProcess()
		{
			if (job)
				CloseHandle(job);
			if (process)
				CloseHandle(process);
		}

		HANDLE Start(std::wstring cmd, const wchar_t *dir)
		{
			if (process)
				return nullptr;
			HANDLE newJob = CreateJobObjectW(nullptr, nullptr);
			if (!newJob)
			{
				printf("Could not create server job (Windows error %lu).\n", GetLastError());
				return nullptr;
			}
			JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
			limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
			if (!SetInformationJobObject(newJob, JobObjectExtendedLimitInformation, &limits, sizeof(limits)))
			{
				printf("Could not configure server job (Windows error %lu).\n", GetLastError());
				CloseHandle(newJob);
				return nullptr;
			}
			STARTUPINFOW si{};
			si.cb = sizeof(si);
			PROCESS_INFORMATION pi{};
			if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE,
			                    CREATE_NEW_PROCESS_GROUP | CREATE_SUSPENDED, nullptr, dir, &si, &pi))
			{
				printf("Could not create server process (Windows error %lu).\n", GetLastError());
				CloseHandle(newJob);
				return nullptr;
			}
			if (!AssignProcessToJobObject(newJob, pi.hProcess))
			{
				printf("Could not assign server to job (Windows error %lu).\n", GetLastError());
				// The child is still suspended and must never be allowed to run.
				TerminateProcess(pi.hProcess, 1);
				CloseHandle(pi.hThread);
				CloseHandle(pi.hProcess);
				CloseHandle(newJob);
				return nullptr;
			}
			if (ResumeThread(pi.hThread) == static_cast<DWORD>(-1))
			{
				printf("Could not resume server process (Windows error %lu).\n", GetLastError());
				CloseHandle(newJob); // kills the assigned child
				CloseHandle(pi.hThread);
				CloseHandle(pi.hProcess);
				return nullptr;
			}
			CloseHandle(pi.hThread);
			job = newJob;
			process = pi.hProcess;
			return process;
		}
	};
}
