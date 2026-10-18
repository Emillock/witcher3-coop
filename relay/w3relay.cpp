// w3relay: carries Witcher Online's UDP traffic over Steam (AppID 480 "Spacewar") so friends join through a
// Steam lobby without IP addresses or port forwarding (the HXCoop relay pattern from coop-anything).
//
//   w3relay host [--server-port 40000] [--server-jar PATH] [--game-dir DIR] [--name NAME] [--no-invite]
//   w3relay join [--lobby ID] [--local-port 40100] [--game-dir DIR] [--name NAME]
//
// Host: creates a friends-only lobby; every remote player gets its own local UDP socket "connected" to the
// Witcher Online server on 127.0.0.1, so the server sees each friend as a separate client.
// Join: binds 127.0.0.1:<local-port> for the game and forwards everything to the lobby owner.
// steam_api64.dll is loaded from next to this exe, else from the game's bin\x64_dx12 (the player's own copy).
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <map>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "ws2_32.lib")

namespace
{
	constexpr uint32_t kAppId = 480;
	constexpr int kDataChannel = 0;
	constexpr int kControlChannel = 1;
	constexpr int kSendUnreliableNoNagle = 1;
	constexpr int kSendReliable = 8;
	constexpr ULONGLONG kKeepaliveMs = 1000;
	constexpr ULONGLONG kPeerTimeoutMs = 20000;
	constexpr const char *kLobbyKey = "w3coop";

	// ---- Steamworks flat API, loaded dynamically (no SDK headers) ----

#pragma pack(push, 8)
	struct CallbackMsg
	{
		int32_t user;
		int32_t callback;
		uint8_t *param;
		int32_t paramSize;
	};
	struct CallCompleted
	{
		uint64_t call;
		int32_t callback;
		uint32_t paramSize;
	};
	struct LobbyCreated
	{
		int32_t result;
		uint64_t lobby;
	};
	struct LobbyEnter
	{
		uint64_t lobby;
		uint32_t permissions;
		bool locked;
		uint32_t response;
	};
	struct LobbyJoinRequested
	{
		uint64_t lobby;
		uint64_t friendId;
	};
	struct RichPresenceJoinRequested
	{
		uint64_t friendId;
		char connect[256];
	};
	struct FriendGameInfo
	{
		uint64_t gameId;
		uint32_t gameIp;
		uint16_t gamePort;
		uint16_t queryPort;
		uint64_t lobby;
	};
#pragma pack(pop)

	struct Identity
	{
		uint8_t bytes[160];
	};

	struct Steam
	{
		HMODULE dll = nullptr;
		void *user = nullptr, *matchmaking = nullptr, *friends = nullptr, *messages = nullptr;
		int32_t pipe = 0;

		int(__cdecl *InitFlat)(char *) = nullptr;
		void(__cdecl *Shutdown)() = nullptr;
		bool(__cdecl *IsSteamRunning)() = nullptr;
		int32_t(__cdecl *GetHSteamPipe)() = nullptr;
		void(__cdecl *DispatchInit)() = nullptr;
		void(__cdecl *DispatchRunFrame)(int32_t) = nullptr;
		bool(__cdecl *DispatchNext)(int32_t, CallbackMsg *) = nullptr;
		void(__cdecl *DispatchFree)(int32_t) = nullptr;
		bool(__cdecl *DispatchCallResult)(int32_t, uint64_t, void *, int, int, bool *) = nullptr;
		void *(__cdecl *GetUser)() = nullptr;
		void *(__cdecl *GetMatchmaking)() = nullptr;
		void *(__cdecl *GetFriends)() = nullptr;
		void *(__cdecl *GetMessages)() = nullptr;
		uint64_t(__cdecl *GetSteamID)(void *) = nullptr;
		bool(__cdecl *LoggedOn)(void *) = nullptr;
		uint64_t(__cdecl *CreateLobby)(void *, int, int) = nullptr;
		uint64_t(__cdecl *JoinLobby)(void *, uint64_t) = nullptr;
		void(__cdecl *LeaveLobby)(void *, uint64_t) = nullptr;
		bool(__cdecl *SetLobbyData)(void *, uint64_t, const char *, const char *) = nullptr;
		const char *(__cdecl *GetLobbyData)(void *, uint64_t, const char *) = nullptr;
		uint64_t(__cdecl *GetLobbyOwner)(void *, uint64_t) = nullptr;
		int(__cdecl *GetNumLobbyMembers)(void *, uint64_t) = nullptr;
		uint64_t(__cdecl *GetLobbyMemberByIndex)(void *, uint64_t, int) = nullptr;
		bool(__cdecl *SetRichPresence)(void *, const char *, const char *) = nullptr;
		void(__cdecl *ClearRichPresence)(void *) = nullptr;
		void(__cdecl *InviteDialog)(void *, uint64_t) = nullptr;
		int(__cdecl *GetFriendCount)(void *, int) = nullptr;
		uint64_t(__cdecl *GetFriendByIndex)(void *, int, int) = nullptr;
		bool(__cdecl *GetFriendGamePlayed)(void *, uint64_t, FriendGameInfo *) = nullptr;
		const char *(__cdecl *GetFriendName)(void *, uint64_t) = nullptr;
		void(__cdecl *IdentitySet)(Identity *, uint64_t) = nullptr;
		uint64_t(__cdecl *IdentityGet)(const void *) = nullptr;
		int(__cdecl *SendToUser)(void *, const Identity *, const void *, uint32_t, int, int) = nullptr;
		int(__cdecl *Receive)(void *, int, void **, int) = nullptr;
		bool(__cdecl *AcceptSession)(void *, const Identity *) = nullptr;
		bool(__cdecl *CloseSession)(void *, const Identity *) = nullptr;
		void(__cdecl *ReleaseMessage)(void *) = nullptr;
	} S;

	template <typename Fn>
	bool Bind(Fn &fn, const char *name)
	{
		fn = reinterpret_cast<Fn>(GetProcAddress(S.dll, name));
		if (!fn)
			printf("steam_api64.dll has no export %s\n", name);
		return fn != nullptr;
	}

	std::wstring ExeDir()
	{
		wchar_t path[MAX_PATH]{};
		GetModuleFileNameW(nullptr, path, MAX_PATH);
		std::wstring s(path);
		return s.substr(0, s.find_last_of(L"\\/"));
	}

	bool LoadSteam(const std::wstring &gameDir)
	{
		const std::wstring local = ExeDir() + L"\\steam_api64.dll";
		S.dll = LoadLibraryW(local.c_str());
		if (!S.dll && !gameDir.empty())
			S.dll = LoadLibraryW((gameDir + L"\\bin\\x64_dx12\\steam_api64.dll").c_str());
		if (!S.dll)
		{
			printf("steam_api64.dll not found next to w3relay.exe or in <game>\\bin\\x64_dx12 (pass --game-dir)\n");
			return false;
		}

		bool ok = Bind(S.InitFlat, "SteamAPI_InitFlat") & Bind(S.Shutdown, "SteamAPI_Shutdown") & Bind(S.IsSteamRunning, "SteamAPI_IsSteamRunning") &
		          Bind(S.GetHSteamPipe, "SteamAPI_GetHSteamPipe") & Bind(S.DispatchInit, "SteamAPI_ManualDispatch_Init") &
		          Bind(S.DispatchRunFrame, "SteamAPI_ManualDispatch_RunFrame") & Bind(S.DispatchNext, "SteamAPI_ManualDispatch_GetNextCallback") &
		          Bind(S.DispatchFree, "SteamAPI_ManualDispatch_FreeLastCallback") & Bind(S.DispatchCallResult, "SteamAPI_ManualDispatch_GetAPICallResult") &
		          Bind(S.GetUser, "SteamAPI_SteamUser_v023") & Bind(S.GetMatchmaking, "SteamAPI_SteamMatchmaking_v009") &
		          Bind(S.GetFriends, "SteamAPI_SteamFriends_v018") & Bind(S.GetMessages, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002") &
		          Bind(S.GetSteamID, "SteamAPI_ISteamUser_GetSteamID") & Bind(S.LoggedOn, "SteamAPI_ISteamUser_BLoggedOn") &
		          Bind(S.CreateLobby, "SteamAPI_ISteamMatchmaking_CreateLobby") & Bind(S.JoinLobby, "SteamAPI_ISteamMatchmaking_JoinLobby") &
		          Bind(S.LeaveLobby, "SteamAPI_ISteamMatchmaking_LeaveLobby") & Bind(S.SetLobbyData, "SteamAPI_ISteamMatchmaking_SetLobbyData") &
		          Bind(S.GetLobbyData, "SteamAPI_ISteamMatchmaking_GetLobbyData") & Bind(S.GetLobbyOwner, "SteamAPI_ISteamMatchmaking_GetLobbyOwner") &
		          Bind(S.GetNumLobbyMembers, "SteamAPI_ISteamMatchmaking_GetNumLobbyMembers") &
		          Bind(S.GetLobbyMemberByIndex, "SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex") &
		          Bind(S.SetRichPresence, "SteamAPI_ISteamFriends_SetRichPresence") & Bind(S.ClearRichPresence, "SteamAPI_ISteamFriends_ClearRichPresence") &
		          Bind(S.InviteDialog, "SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog") &
		          Bind(S.GetFriendCount, "SteamAPI_ISteamFriends_GetFriendCount") & Bind(S.GetFriendByIndex, "SteamAPI_ISteamFriends_GetFriendByIndex") &
		          Bind(S.GetFriendGamePlayed, "SteamAPI_ISteamFriends_GetFriendGamePlayed") &
		          Bind(S.GetFriendName, "SteamAPI_ISteamFriends_GetFriendPersonaName") &
		          Bind(S.IdentitySet, "SteamAPI_SteamNetworkingIdentity_SetSteamID64") & Bind(S.IdentityGet, "SteamAPI_SteamNetworkingIdentity_GetSteamID64") &
		          Bind(S.SendToUser, "SteamAPI_ISteamNetworkingMessages_SendMessageToUser") &
		          Bind(S.Receive, "SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel") &
		          Bind(S.AcceptSession, "SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser") &
		          Bind(S.CloseSession, "SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser") &
		          Bind(S.ReleaseMessage, "SteamAPI_SteamNetworkingMessage_t_Release");
		return ok;
	}

	bool InitSteam()
	{
		// Spacewar: every Steam user may run it, it has lobbies and relayed P2P
		SetEnvironmentVariableW(L"SteamAppId", L"480");
		SetEnvironmentVariableW(L"SteamGameId", L"480");
		std::ofstream(ExeDir() + L"\\steam_appid.txt") << kAppId;
		SetCurrentDirectoryW(ExeDir().c_str());

		if (!S.IsSteamRunning())
		{
			printf("Steam is not running. Start Steam and log in, then run w3relay again.\n");
			return false;
		}
		char error[1024]{};
		const int result = S.InitFlat(error);
		if (result != 0)
		{
			printf("Steam init failed (%d): %s\n", result, error);
			return false;
		}
		S.DispatchInit();
		S.pipe = S.GetHSteamPipe();
		S.user = S.GetUser();
		S.matchmaking = S.GetMatchmaking();
		S.friends = S.GetFriends();
		S.messages = S.GetMessages();
		if (!S.LoggedOn(S.user))
		{
			printf("Steam is running but not logged in.\n");
			return false;
		}
		return true;
	}

	Identity MakeIdentity(uint64_t steamId)
	{
		Identity id{};
		S.IdentitySet(&id, steamId);
		return id;
	}

	bool SendTo(uint64_t steamId, const void *data, uint32_t size, int flags, int channel)
	{
		const Identity id = MakeIdentity(steamId);
		return S.SendToUser(S.messages, &id, data, size, flags, channel) == 1;
	}

	// SteamNetworkingMessage_t on x64: data pointer at 0, size at 8, sender identity at 16.
	struct Message
	{
		void *raw;
		const uint8_t *data() const { return *reinterpret_cast<uint8_t *const *>(raw); }
		int size() const { return *reinterpret_cast<const int32_t *>(static_cast<const uint8_t *>(raw) + 8); }
		uint64_t sender() const { return S.IdentityGet(static_cast<const uint8_t *>(raw) + 16); }
	};

	// ---- UDP helpers ----

	SOCKET UdpSocket(uint16_t bindPort)
	{
		SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
		sockaddr_in addr{};
		addr.sin_family = AF_INET;
		addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
		addr.sin_port = htons(bindPort);
		if (bind(s, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0)
		{
			closesocket(s);
			return INVALID_SOCKET;
		}
		u_long nonBlocking = 1;
		ioctlsocket(s, FIONBIO, &nonBlocking);
		// a previous peer port being closed must not kill the socket (WSAECONNRESET on UDP)
		BOOL off = FALSE;
		DWORD ignored = 0;
		WSAIoctl(s, _WSAIOW(IOC_VENDOR, 12), &off, sizeof(off), nullptr, 0, &ignored, nullptr, nullptr);
		return s;
	}

	sockaddr_in Loopback(uint16_t port)
	{
		sockaddr_in addr{};
		addr.sin_family = AF_INET;
		addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
		addr.sin_port = htons(port);
		return addr;
	}

	// ---- state ----

	volatile bool g_quit = false;
	bool g_isHost = false;
	uint64_t g_lobby = 0;
	uint64_t g_host = 0;
	uint64_t g_pendingJoin = 0;
	uint64_t g_trafficIn = 0, g_trafficOut = 0;
	bool g_trafficAnnounced = false;

	struct Peer
	{
		SOCKET socket = INVALID_SOCKET;
		ULONGLONG lastSeen = 0;
		ULONGLONG lastKeepalive = 0;
	};
	std::map<uint64_t, Peer> g_peers;
	// session requests from players the lobby member list doesn't show yet (it syncs a little later)
	std::map<uint64_t, ULONGLONG> g_pendingSessions;

	BOOL WINAPI OnConsoleCtrl(DWORD)
	{
		g_quit = true;
		return TRUE;
	}

	bool IsLobbyMember(uint64_t steamId)
	{
		const int n = S.GetNumLobbyMembers(S.matchmaking, g_lobby);
		for (int i = 0; i < n; ++i)
		{
			if (S.GetLobbyMemberByIndex(S.matchmaking, g_lobby, i) == steamId)
				return true;
		}
		return false;
	}

	void AnnounceTraffic()
	{
		if (!g_trafficAnnounced && g_trafficIn > 0 && g_trafficOut > 0)
		{
			g_trafficAnnounced = true;
			printf("Game traffic is flowing through Steam in both directions.\n");
		}
	}

	void SendControl(uint64_t steamId, const char *text)
	{
		SendTo(steamId, text, static_cast<uint32_t>(strlen(text)), kSendReliable, kControlChannel);
	}

	void DropPeer(uint64_t steamId, const char *why)
	{
		auto it = g_peers.find(steamId);
		if (it == g_peers.end())
			return;
		printf("Player %s left (%s).\n", S.GetFriendName(S.friends, steamId), why);
		if (it->second.socket != INVALID_SOCKET)
			closesocket(it->second.socket);
		const Identity id = MakeIdentity(steamId);
		S.CloseSession(S.messages, &id);
		g_peers.erase(it);
	}

	void HandleCallback(int id, const uint8_t *param)
	{
		switch (id)
		{
		case 513: {
			// real Steam delivers this both as the call result and as a broadcast callback
			const auto *created = reinterpret_cast<const LobbyCreated *>(param);
			if (created->result == 1 && created->lobby == g_lobby)
				break;
			if (created->result != 1)
			{
				printf("Could not create a Steam lobby (result %d).\n", created->result);
				g_quit = true;
				break;
			}
			g_lobby = created->lobby;
			S.SetLobbyData(S.matchmaking, g_lobby, kLobbyKey, "1");
			const std::string connect = "+connect_lobby " + std::to_string(g_lobby);
			S.SetRichPresence(S.friends, "connect", connect.c_str());
			S.SetRichPresence(S.friends, "status", "Hosting Witcher 3 co-op");
			printf("Lobby ready: %llu. Friends can join from your Steam profile, or with: w3relay join --lobby %llu\n",
			       static_cast<unsigned long long>(g_lobby), static_cast<unsigned long long>(g_lobby));
			break;
		}
		case 504: {
			// the host also gets this for its own new lobby
			const auto *enter = reinterpret_cast<const LobbyEnter *>(param);
			if (g_isHost)
				break;
			if (enter->response != 1)
			{
				printf("Could not join lobby %llu (response %u).\n", static_cast<unsigned long long>(enter->lobby), enter->response);
				g_pendingJoin = 0;
				break;
			}
			if (g_host != 0)
				break;
			const char *tag = S.GetLobbyData(S.matchmaking, enter->lobby, kLobbyKey);
			if (!tag || strcmp(tag, "1") != 0)
			{
				printf("That lobby is not a Witcher 3 co-op game; leaving it.\n");
				S.LeaveLobby(S.matchmaking, enter->lobby);
				g_pendingJoin = 0;
				break;
			}
			g_lobby = enter->lobby;
			g_host = S.GetLobbyOwner(S.matchmaking, g_lobby);
			printf("Joined %s's game (lobby %llu).\n", S.GetFriendName(S.friends, g_host), static_cast<unsigned long long>(g_lobby));
			SendControl(g_host, "hello");
			break;
		}
		case 333: {
			const auto *request = reinterpret_cast<const LobbyJoinRequested *>(param);
			if (!g_isHost && g_host == 0)
				g_pendingJoin = request->lobby;
			break;
		}
		case 337: {
			const auto *request = reinterpret_cast<const RichPresenceJoinRequested *>(param);
			const char *p = strstr(request->connect, "+connect_lobby ");
			if (p && !g_isHost && g_host == 0)
				g_pendingJoin = _strtoui64(p + 15, nullptr, 10);
			break;
		}
		case 1251: {
			// first message from someone: the host accepts lobby members, a client only the host
			const uint64_t from = S.IdentityGet(param);
			const bool ok = g_isHost ? IsLobbyMember(from) : (g_host != 0 && from == g_host);
			if (ok)
				S.AcceptSession(S.messages, reinterpret_cast<const Identity *>(param));
			else if (g_isHost)
				g_pendingSessions[from] = GetTickCount64();
			break;
		}
		}
	}

	void PumpCallbacks()
	{
		CallbackMsg msg{};
		S.DispatchRunFrame(S.pipe);
		while (S.DispatchNext(S.pipe, &msg))
		{
			if (msg.callback == 703)
			{
				const auto *done = reinterpret_cast<const CallCompleted *>(msg.param);
				std::vector<uint8_t> result(done->paramSize);
				bool failed = false;
				if (S.DispatchCallResult(S.pipe, done->call, result.data(), static_cast<int>(result.size()), done->callback, &failed) && !failed)
					HandleCallback(done->callback, result.data());
			}
			else
			{
				HandleCallback(msg.callback, msg.param);
			}
			S.DispatchFree(S.pipe);
		}
	}

	template <typename Handler>
	void DrainSteam(int channel, Handler handler)
	{
		void *batch[64];
		int n;
		while ((n = S.Receive(S.messages, channel, batch, 64)) > 0)
		{
			for (int i = 0; i < n; ++i)
			{
				handler(Message{batch[i]});
				S.ReleaseMessage(batch[i]);
			}
		}
	}

	// ---- config.xml of Witcher Online ----

	void PointGameAtRelay(const std::wstring &gameDir, uint16_t port, const std::string &name)
	{
		const std::wstring path = gameDir + L"\\bin\\WitcherOnline\\config.xml";
		std::ifstream in(path);
		if (!in)
		{
			printf("No Witcher Online config.xml in the game folder; set ServerIP 127.0.0.1 and Port %u yourself.\n", port);
			return;
		}
		std::stringstream buffer;
		buffer << in.rdbuf();
		in.close();
		std::string xml = buffer.str();
		const std::wstring backup = path + L".before-w3relay";
		if (GetFileAttributesW(backup.c_str()) == INVALID_FILE_ATTRIBUTES)
			std::ofstream(backup) << xml;
		xml = std::regex_replace(xml, std::regex("<ServerIP>[^<]*</ServerIP>"), "<ServerIP>127.0.0.1</ServerIP>");
		xml = std::regex_replace(xml, std::regex("<Port>[^<]*</Port>"), "<Port>" + std::to_string(port) + "</Port>");
		if (!name.empty())
			xml = std::regex_replace(xml, std::regex("<Username>[^<]*</Username>"), "<Username>" + name + "</Username>");
		std::ofstream(path) << xml;
		printf("Witcher Online now connects to 127.0.0.1:%u (previous config kept as config.xml.before-w3relay).\n", port);
	}

	// ---- host ----

	HANDLE StartServer(const std::wstring &jar, uint16_t port)
	{
		std::wstring cmd = L"java -jar \"" + jar + L"\" " + std::to_wstring(port);
		STARTUPINFOW si{sizeof(si)};
		PROCESS_INFORMATION pi{};
		const std::wstring dir = jar.substr(0, jar.find_last_of(L"\\/"));
		if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NEW_PROCESS_GROUP, nullptr, dir.c_str(), &si, &pi))
		{
			printf("Could not start the Witcher Online server (is Java 21 installed?).\n");
			return nullptr;
		}
		// the server never outlives the relay
		HANDLE job = CreateJobObjectW(nullptr, nullptr);
		JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
		limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
		SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
		AssignProcessToJobObject(job, pi.hProcess);
		CloseHandle(pi.hThread);
		printf("Witcher Online server started on UDP %u.\n", port);
		return pi.hProcess;
	}

	int RunHost(uint16_t serverPort, const std::wstring &jar, bool invite)
	{
		HANDLE server = jar.empty() ? nullptr : StartServer(jar, serverPort);
		const sockaddr_in serverAddr = Loopback(serverPort);
		const uint64_t self = S.GetSteamID(S.user);
		S.CreateLobby(S.matchmaking, 1, 8);
		bool invited = false;
		char buffer[65536];

		while (!g_quit)
		{
			PumpCallbacks();
			if (g_lobby && invite && !invited)
			{
				S.InviteDialog(S.friends, g_lobby);
				invited = true;
			}
			for (auto it = g_pendingSessions.begin(); it != g_pendingSessions.end();)
			{
				if (IsLobbyMember(it->first))
				{
					const Identity id = MakeIdentity(it->first);
					S.AcceptSession(S.messages, &id);
					it = g_pendingSessions.erase(it);
				}
				else if (GetTickCount64() - it->second > 30000)
				{
					printf("Ignored traffic from a Steam user who is not in the lobby.\n");
					it = g_pendingSessions.erase(it);
				}
				else
				{
					++it;
				}
			}

			DrainSteam(kDataChannel, [&](const Message &m) {
				const uint64_t from = m.sender();
				if (from == self || !IsLobbyMember(from))
					return;
				Peer &peer = g_peers[from];
				if (peer.socket == INVALID_SOCKET)
				{
					peer.socket = UdpSocket(0);
					connect(peer.socket, reinterpret_cast<const sockaddr *>(&serverAddr), sizeof(serverAddr));
					printf("Player %s connected.\n", S.GetFriendName(S.friends, from));
				}
				peer.lastSeen = GetTickCount64();
				send(peer.socket, reinterpret_cast<const char *>(m.data()), m.size(), 0);
				++g_trafficIn;
			});
			DrainSteam(kControlChannel, [&](const Message &m) {
				const uint64_t from = m.sender();
				if (from == self || !IsLobbyMember(from))
					return;
				if (m.size() == 3 && memcmp(m.data(), "bye", 3) == 0)
				{
					DropPeer(from, "said goodbye");
					return;
				}
				// a friend still loading the game sends only keep-alives; answer them too
				Peer &peer = g_peers[from];
				peer.lastSeen = GetTickCount64();
			});

			const ULONGLONG now = GetTickCount64();
			std::vector<uint64_t> gone;
			for (auto &[steamId, peer] : g_peers)
			{
				int got;
				while (peer.socket != INVALID_SOCKET && (got = recv(peer.socket, buffer, sizeof(buffer), 0)) > 0)
				{
					SendTo(steamId, buffer, static_cast<uint32_t>(got), kSendUnreliableNoNagle, kDataChannel);
					++g_trafficOut;
				}
				if (now - peer.lastKeepalive >= kKeepaliveMs)
				{
					SendControl(steamId, "ping");
					peer.lastKeepalive = now;
				}
				if (now - peer.lastSeen > kPeerTimeoutMs)
					gone.push_back(steamId);
			}
			for (uint64_t steamId : gone)
				DropPeer(steamId, "no traffic for 20 s");
			AnnounceTraffic();
			if (server && WaitForSingleObject(server, 0) == WAIT_OBJECT_0)
			{
				printf("The Witcher Online server stopped.\n");
				break;
			}
			Sleep(1);
		}

		for (auto &entry : g_peers)
			SendControl(entry.first, "bye");
		if (server)
		{
			GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, GetProcessId(server));
			WaitForSingleObject(server, 3000);
			TerminateProcess(server, 0);
		}
		return 0;
	}

	// ---- join ----

	uint64_t FindHostingFriend()
	{
		const int n = S.GetFriendCount(S.friends, 4);
		for (int i = 0; i < n; ++i)
		{
			const uint64_t friendId = S.GetFriendByIndex(S.friends, i, 4);
			FriendGameInfo info{};
			if (S.GetFriendGamePlayed(S.friends, friendId, &info) && (info.gameId & 0xFFFFFF) == kAppId && info.lobby)
			{
				printf("Found %s hosting.\n", S.GetFriendName(S.friends, friendId));
				return info.lobby;
			}
		}
		return 0;
	}

	int RunJoin(uint64_t lobby, uint16_t localPort)
	{
		SOCKET local = UdpSocket(localPort);
		if (local == INVALID_SOCKET)
		{
			printf("UDP port %u on 127.0.0.1 is busy; pick another with --local-port.\n", localPort);
			return 1;
		}
		g_pendingJoin = lobby;
		sockaddr_in game{};
		bool haveGame = false;
		ULONGLONG lastSearch = 0, lastKeepalive = 0, lastHostTraffic = GetTickCount64();
		char buffer[65536];

		if (!lobby)
			printf("Looking for a friend hosting Witcher 3 co-op (or accept their Steam invite)...\n");

		while (!g_quit)
		{
			PumpCallbacks();
			const ULONGLONG now = GetTickCount64();

			if (g_host == 0)
			{
				if (!g_pendingJoin && now - lastSearch > 3000)
				{
					g_pendingJoin = FindHostingFriend();
					lastSearch = now;
				}
				if (g_pendingJoin)
				{
					S.JoinLobby(S.matchmaking, g_pendingJoin);
					g_pendingJoin = 0;
					lastSearch = now;
				}
				lastHostTraffic = now;
				Sleep(20);
				continue;
			}

			sockaddr_in from{};
			int fromLen = sizeof(from);
			int got;
			while ((got = recvfrom(local, buffer, sizeof(buffer), 0, reinterpret_cast<sockaddr *>(&from), &fromLen)) > 0)
			{
				game = from;
				haveGame = true;
				SendTo(g_host, buffer, static_cast<uint32_t>(got), kSendUnreliableNoNagle, kDataChannel);
				++g_trafficOut;
				fromLen = sizeof(from);
			}
			DrainSteam(kDataChannel, [&](const Message &m) {
				if (m.sender() != g_host)
					return;
				lastHostTraffic = now;
				if (haveGame)
				{
					sendto(local, reinterpret_cast<const char *>(m.data()), m.size(), 0, reinterpret_cast<const sockaddr *>(&game), sizeof(game));
					++g_trafficIn;
				}
			});
			DrainSteam(kControlChannel, [&](const Message &m) {
				if (m.sender() != g_host)
					return;
				lastHostTraffic = now;
				if (m.size() == 3 && memcmp(m.data(), "bye", 3) == 0)
				{
					printf("The host closed the game.\n");
					g_quit = true;
				}
			});
			if (now - lastKeepalive >= kKeepaliveMs)
			{
				SendControl(g_host, "ping");
				lastKeepalive = now;
			}
			if (now - lastHostTraffic > kPeerTimeoutMs)
			{
				printf("Lost the host (no traffic for 20 s); looking for the game again.\n");
				S.LeaveLobby(S.matchmaking, g_lobby);
				const Identity id = MakeIdentity(g_host);
				S.CloseSession(S.messages, &id);
				g_host = 0;
				g_lobby = 0;
				g_pendingJoin = lobby;
				lastSearch = 0;
				continue;
			}
			AnnounceTraffic();
			Sleep(1);
		}

		if (g_host)
			SendControl(g_host, "bye");
		closesocket(local);
		return 0;
	}

	void Usage()
	{
		printf("w3relay host [--server-port 40000] [--server-jar PATH] [--game-dir DIR] [--name NAME] [--no-invite]\n"
		       "w3relay join [--lobby ID] [--local-port 40100] [--game-dir DIR] [--name NAME]\n");
	}
} // namespace

int wmain(int argc, wchar_t **argv)
{
	setvbuf(stdout, nullptr, _IONBF, 0);
	if (argc < 2)
	{
		Usage();
		return 2;
	}

	const std::wstring mode = argv[1];
	uint16_t serverPort = 40000, localPort = 40100;
	uint64_t lobby = 0;
	std::wstring jar, gameDir;
	std::string name;
	bool invite = true;
	for (int i = 2; i < argc; ++i)
	{
		const std::wstring arg = argv[i];
		const bool hasValue = i + 1 < argc;
		if (arg == L"--server-port" && hasValue)
			serverPort = static_cast<uint16_t>(_wtoi(argv[++i]));
		else if (arg == L"--local-port" && hasValue)
			localPort = static_cast<uint16_t>(_wtoi(argv[++i]));
		else if ((arg == L"--lobby" || arg == L"+connect_lobby") && hasValue)
			lobby = _wcstoui64(argv[++i], nullptr, 10);
		else if (arg == L"--server-jar" && hasValue)
			jar = argv[++i];
		else if (arg == L"--game-dir" && hasValue)
			gameDir = argv[++i];
		else if (arg == L"--name" && hasValue)
		{
			// Witcher Online accepts letters, digits and _ (2-16 characters)
			for (const wchar_t c : std::wstring(argv[++i]))
			{
				if (name.size() < 16 && ((c >= L'a' && c <= L'z') || (c >= L'A' && c <= L'Z') || (c >= L'0' && c <= L'9') || c == L'_'))
					name += static_cast<char>(c);
			}
		}
		else if (arg == L"--no-invite")
			invite = false;
		else
		{
			Usage();
			return 2;
		}
	}

	WSADATA wsa{};
	WSAStartup(MAKEWORD(2, 2), &wsa);
	SetConsoleCtrlHandler(OnConsoleCtrl, TRUE);

	if (!LoadSteam(gameDir) || !InitSteam())
		return 1;

	int rc;
	if (mode == L"host")
	{
		g_isHost = true;
		if (!gameDir.empty())
			PointGameAtRelay(gameDir, serverPort, name);
		rc = RunHost(serverPort, jar, invite);
	}
	else if (mode == L"join")
	{
		if (!gameDir.empty())
			PointGameAtRelay(gameDir, localPort, name);
		rc = RunJoin(lobby, localPort);
	}
	else
	{
		Usage();
		rc = 2;
	}

	if (g_lobby)
		S.LeaveLobby(S.matchmaking, g_lobby);
	S.ClearRichPresence(S.friends);
	S.Shutdown();
	WSACleanup();
	return rc;
}
