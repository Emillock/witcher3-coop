// Mock steam_api64.dll for testing w3relay with two "Steam users" on one PC (one PC can only run one real
// Steam account). Exports the flat-API functions w3relay uses.
// Env: MOCK_STEAM_DIR (shared folder: ports, lobbies), MOCK_STEAM_ID (this process's SteamID), MOCK_STEAM_NAME.
// Lobbies are files in MOCK_STEAM_DIR; messages are localhost UDP datagrams. Like real Steam, messages from a
// stranger are held until AcceptSessionWithUser (callback 1251 announces them).
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "ws2_32.lib")

#define EXPORT extern "C" __declspec(dllexport)

namespace
{
	constexpr uint64_t kLobbyBase = 0x0186000000000000ull;
	constexpr uint32_t kMagic = 0x4B4D3357; // "W3MK"

	struct Pending
	{
		int callback;
		std::vector<uint8_t> data;
	};

	struct Incoming
	{
		uint64_t sender;
		int channel;
		std::vector<uint8_t> data;
	};

	std::mutex g_mutex;
	std::string g_dir;
	std::string g_name = "mock";
	uint64_t g_self = 0;
	SOCKET g_socket = INVALID_SOCKET;
	std::deque<Pending> g_callbacks;
	std::map<uint64_t, Pending> g_callResults;
	uint64_t g_nextCall = 1;
	std::vector<uint8_t> g_current;
	std::set<uint64_t> g_accepted;
	std::set<uint64_t> g_requested;
	std::vector<Incoming> g_held;
	std::map<int, std::deque<Incoming>> g_channels;
	std::map<std::string, std::string> g_richPresence;

	std::string Env(const char *name, const char *fallback = "")
	{
		char buffer[1024];
		const DWORD n = GetEnvironmentVariableA(name, buffer, sizeof(buffer));
		return (n > 0 && n < sizeof(buffer)) ? std::string(buffer, n) : std::string(fallback);
	}

	std::string Path(const std::string &name)
	{
		return g_dir + "\\" + name;
	}

	std::string ReadFile(const std::string &name)
	{
		std::ifstream in(Path(name));
		std::stringstream s;
		s << in.rdbuf();
		return s.str();
	}

	void WriteFile(const std::string &name, const std::string &text)
	{
		std::ofstream(Path(name)) << text;
	}

	bool Exists(const std::string &name)
	{
		return GetFileAttributesA(Path(name).c_str()) != INVALID_FILE_ATTRIBUTES;
	}

	std::vector<uint64_t> ListIds(const char *prefix, const char *suffix)
	{
		std::vector<uint64_t> out;
		WIN32_FIND_DATAA fd;
		HANDLE h = FindFirstFileA(Path(std::string(prefix) + "*" + suffix).c_str(), &fd);
		if (h == INVALID_HANDLE_VALUE)
			return out;
		do
		{
			out.push_back(_strtoui64(fd.cFileName + strlen(prefix), nullptr, 10));
		} while (FindNextFileA(h, &fd));
		FindClose(h);
		return out;
	}

	std::vector<uint64_t> Members(uint64_t lobby)
	{
		std::vector<uint64_t> out;
		std::stringstream s(ReadFile("lobby_" + std::to_string(lobby) + ".members"));
		uint64_t id;
		while (s >> id)
			out.push_back(id);
		return out;
	}

	void QueueCallback(int id, const void *data, size_t size)
	{
		g_callbacks.push_back({id, std::vector<uint8_t>(static_cast<const uint8_t *>(data), static_cast<const uint8_t *>(data) + size)});
	}

	uint64_t QueueCallResult(int id, const void *data, size_t size)
	{
		const uint64_t call = g_nextCall++;
		g_callResults[call] = {id, std::vector<uint8_t>(static_cast<const uint8_t *>(data), static_cast<const uint8_t *>(data) + size)};
#pragma pack(push, 8)
		struct
		{
			uint64_t call;
			int32_t callback;
			uint32_t size;
		} done{call, id, static_cast<uint32_t>(size)};
#pragma pack(pop)
		QueueCallback(703, &done, sizeof(done));
		return call;
	}

	// identity layout used by this mock only: type at 0 (16 = SteamID), id at 8
	void SetIdentity(void *identity, uint64_t id)
	{
		memset(identity, 0, 136);
		*static_cast<int32_t *>(identity) = 16;
		memcpy(static_cast<uint8_t *>(identity) + 8, &id, 8);
	}

	uint64_t GetIdentity(const void *identity)
	{
		uint64_t id;
		memcpy(&id, static_cast<const uint8_t *>(identity) + 8, 8);
		return id;
	}

	uint16_t PortOf(uint64_t id)
	{
		return static_cast<uint16_t>(atoi(ReadFile("user_" + std::to_string(id) + ".port").c_str()));
	}

	void Poll()
	{
		uint8_t buffer[65536 + 32];
		int got;
		while ((got = recv(g_socket, reinterpret_cast<char *>(buffer), sizeof(buffer), 0)) >= 14)
		{
			uint32_t magic;
			memcpy(&magic, buffer, 4);
			if (magic != kMagic)
				continue;
			Incoming in;
			in.channel = buffer[4];
			memcpy(&in.sender, buffer + 6, 8);
			in.data.assign(buffer + 14, buffer + got);
			if (g_accepted.count(in.sender))
			{
				g_channels[in.channel].push_back(std::move(in));
				continue;
			}
			if (!g_requested.count(in.sender))
			{
				g_requested.insert(in.sender);
				uint8_t identity[136];
				SetIdentity(identity, in.sender);
				QueueCallback(1251, identity, sizeof(identity));
			}
			g_held.push_back(std::move(in));
		}
	}
} // namespace

EXPORT bool SteamAPI_IsSteamRunning()
{
	return true;
}

EXPORT int SteamAPI_InitFlat(char *error)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	g_dir = Env("MOCK_STEAM_DIR");
	g_self = _strtoui64(Env("MOCK_STEAM_ID", "0").c_str(), nullptr, 10);
	g_name = Env("MOCK_STEAM_NAME", "mock");
	if (g_dir.empty() || g_self == 0)
	{
		strcpy_s(error, 1024, "mock: set MOCK_STEAM_DIR and MOCK_STEAM_ID");
		return 1;
	}
	WSADATA wsa;
	WSAStartup(MAKEWORD(2, 2), &wsa);
	g_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	sockaddr_in addr{};
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	bind(g_socket, reinterpret_cast<sockaddr *>(&addr), sizeof(addr));
	int len = sizeof(addr);
	getsockname(g_socket, reinterpret_cast<sockaddr *>(&addr), &len);
	u_long nonBlocking = 1;
	ioctlsocket(g_socket, FIONBIO, &nonBlocking);
	WriteFile("user_" + std::to_string(g_self) + ".port", std::to_string(ntohs(addr.sin_port)));
	WriteFile("user_" + std::to_string(g_self) + ".name", g_name);
	return 0;
}

EXPORT void SteamAPI_Shutdown()
{
	std::lock_guard<std::mutex> lock(g_mutex);
	DeleteFileA(Path("user_" + std::to_string(g_self) + ".port").c_str());
	DeleteFileA(Path("user_" + std::to_string(g_self) + ".game").c_str());
	closesocket(g_socket);
}

EXPORT int32_t SteamAPI_GetHSteamPipe()
{
	return 1;
}

EXPORT void SteamAPI_ManualDispatch_Init() {}

EXPORT void SteamAPI_ManualDispatch_RunFrame(int32_t)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	Poll();
}

EXPORT bool SteamAPI_ManualDispatch_GetNextCallback(int32_t, void *msg)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	if (g_callbacks.empty())
		return false;
	g_current = std::move(g_callbacks.front().data);
	const int id = g_callbacks.front().callback;
	g_callbacks.pop_front();
#pragma pack(push, 8)
	struct
	{
		int32_t user;
		int32_t callback;
		uint8_t *param;
		int32_t size;
	} *out = static_cast<decltype(out)>(msg);
#pragma pack(pop)
	out->user = 1;
	out->callback = id;
	out->param = g_current.data();
	out->size = static_cast<int32_t>(g_current.size());
	return true;
}

EXPORT void SteamAPI_ManualDispatch_FreeLastCallback(int32_t) {}

EXPORT bool SteamAPI_ManualDispatch_GetAPICallResult(int32_t, uint64_t call, void *out, int size, int expected, bool *failed)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	auto it = g_callResults.find(call);
	if (it == g_callResults.end() || it->second.callback != expected)
		return false;
	memcpy(out, it->second.data.data(), (std::min)(static_cast<size_t>(size), it->second.data.size()));
	*failed = false;
	g_callResults.erase(it);
	return true;
}

// interface "pointers" are just non-null tags
EXPORT void *SteamAPI_SteamUser_v023() { return reinterpret_cast<void *>(1); }
EXPORT void *SteamAPI_SteamMatchmaking_v009() { return reinterpret_cast<void *>(2); }
EXPORT void *SteamAPI_SteamFriends_v018() { return reinterpret_cast<void *>(3); }
EXPORT void *SteamAPI_SteamNetworkingMessages_SteamAPI_v002() { return reinterpret_cast<void *>(4); }

EXPORT uint64_t SteamAPI_ISteamUser_GetSteamID(void *) { return g_self; }
EXPORT bool SteamAPI_ISteamUser_BLoggedOn(void *) { return true; }

EXPORT uint64_t SteamAPI_ISteamMatchmaking_CreateLobby(void *, int, int)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	const uint64_t lobby = kLobbyBase | g_self;
	WriteFile("lobby_" + std::to_string(lobby) + ".owner", std::to_string(g_self));
	WriteFile("lobby_" + std::to_string(lobby) + ".members", std::to_string(g_self) + "\n");
	WriteFile("user_" + std::to_string(g_self) + ".game", std::to_string(lobby));
#pragma pack(push, 8)
	struct
	{
		int32_t result;
		uint64_t lobby;
	} created{1, lobby};
	struct
	{
		uint64_t lobby;
		uint32_t permissions;
		bool locked;
		uint32_t response;
	} enter{lobby, 0, false, 1};
#pragma pack(pop)
	QueueCallback(504, &enter, sizeof(enter));
	return QueueCallResult(513, &created, sizeof(created));
}

EXPORT uint64_t SteamAPI_ISteamMatchmaking_JoinLobby(void *, uint64_t lobby)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	const bool exists = Exists("lobby_" + std::to_string(lobby) + ".owner");
	if (exists)
		std::ofstream(Path("lobby_" + std::to_string(lobby) + ".members"), std::ios::app) << g_self << "\n";
#pragma pack(push, 8)
	struct
	{
		uint64_t lobby;
		uint32_t permissions;
		bool locked;
		uint32_t response;
	} enter{lobby, 0, false, exists ? 1u : 2u};
#pragma pack(pop)
	return QueueCallResult(504, &enter, sizeof(enter));
}

EXPORT void SteamAPI_ISteamMatchmaking_LeaveLobby(void *, uint64_t lobby)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	std::stringstream keep;
	for (uint64_t id : Members(lobby))
	{
		if (id != g_self)
			keep << id << "\n";
	}
	WriteFile("lobby_" + std::to_string(lobby) + ".members", keep.str());
	if (ReadFile("lobby_" + std::to_string(lobby) + ".owner") == std::to_string(g_self))
		DeleteFileA(Path("lobby_" + std::to_string(lobby) + ".owner").c_str());
}

EXPORT bool SteamAPI_ISteamMatchmaking_SetLobbyData(void *, uint64_t lobby, const char *key, const char *value)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	WriteFile("lobby_" + std::to_string(lobby) + ".data_" + key, value);
	return true;
}

EXPORT const char *SteamAPI_ISteamMatchmaking_GetLobbyData(void *, uint64_t lobby, const char *key)
{
	static thread_local std::string value;
	std::lock_guard<std::mutex> lock(g_mutex);
	value = ReadFile("lobby_" + std::to_string(lobby) + ".data_" + key);
	return value.c_str();
}

EXPORT uint64_t SteamAPI_ISteamMatchmaking_GetLobbyOwner(void *, uint64_t lobby)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	return _strtoui64(ReadFile("lobby_" + std::to_string(lobby) + ".owner").c_str(), nullptr, 10);
}

EXPORT int SteamAPI_ISteamMatchmaking_GetNumLobbyMembers(void *, uint64_t lobby)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	return static_cast<int>(Members(lobby).size());
}

EXPORT uint64_t SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex(void *, uint64_t lobby, int index)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	const auto members = Members(lobby);
	return (index >= 0 && index < static_cast<int>(members.size())) ? members[index] : 0;
}

EXPORT bool SteamAPI_ISteamFriends_SetRichPresence(void *, const char *key, const char *value)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	g_richPresence[key] = value ? value : "";
	return true;
}

EXPORT void SteamAPI_ISteamFriends_ClearRichPresence(void *)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	g_richPresence.clear();
}

EXPORT void SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog(void *, uint64_t) {}

EXPORT int SteamAPI_ISteamFriends_GetFriendCount(void *, int)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	int n = 0;
	for (uint64_t id : ListIds("user_", ".port"))
		n += id != g_self;
	return n;
}

EXPORT uint64_t SteamAPI_ISteamFriends_GetFriendByIndex(void *, int index, int)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	std::vector<uint64_t> others;
	for (uint64_t id : ListIds("user_", ".port"))
	{
		if (id != g_self)
			others.push_back(id);
	}
	return (index >= 0 && index < static_cast<int>(others.size())) ? others[index] : 0;
}

EXPORT bool SteamAPI_ISteamFriends_GetFriendGamePlayed(void *, uint64_t friendId, void *info)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	const std::string game = "user_" + std::to_string(friendId) + ".game";
	if (!Exists(game))
		return false;
#pragma pack(push, 8)
	struct
	{
		uint64_t gameId;
		uint32_t ip;
		uint16_t port;
		uint16_t queryPort;
		uint64_t lobby;
	} *out = static_cast<decltype(out)>(info);
#pragma pack(pop)
	memset(out, 0, sizeof(*out));
	out->gameId = 480;
	out->lobby = _strtoui64(ReadFile(game).c_str(), nullptr, 10);
	return true;
}

EXPORT const char *SteamAPI_ISteamFriends_GetFriendPersonaName(void *, uint64_t id)
{
	static thread_local std::string name;
	std::lock_guard<std::mutex> lock(g_mutex);
	name = ReadFile("user_" + std::to_string(id) + ".name");
	if (name.empty())
		name = std::to_string(id);
	return name.c_str();
}

EXPORT void SteamAPI_SteamNetworkingIdentity_SetSteamID64(void *identity, uint64_t id)
{
	SetIdentity(identity, id);
}

EXPORT uint64_t SteamAPI_SteamNetworkingIdentity_GetSteamID64(const void *identity)
{
	return GetIdentity(identity);
}

EXPORT int SteamAPI_ISteamNetworkingMessages_SendMessageToUser(void *, const void *identity, const void *data, uint32_t size, int, int channel)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	const uint16_t port = PortOf(GetIdentity(identity));
	if (!port || size > 65536)
		return 3; // k_EResultNoConnection-ish
	std::vector<uint8_t> packet(14 + size);
	memcpy(packet.data(), &kMagic, 4);
	packet[4] = static_cast<uint8_t>(channel);
	packet[5] = 0;
	memcpy(packet.data() + 6, &g_self, 8);
	memcpy(packet.data() + 14, data, size);
	sockaddr_in to{};
	to.sin_family = AF_INET;
	to.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	to.sin_port = htons(port);
	sendto(g_socket, reinterpret_cast<const char *>(packet.data()), static_cast<int>(packet.size()), 0, reinterpret_cast<sockaddr *>(&to), sizeof(to));
	return 1;
}

// x64 SteamNetworkingMessage_t prefix: data at 0, size at 8, sender identity at 16
struct MockMessage
{
	void *data;
	int32_t size;
	uint32_t conn;
	uint8_t identity[136];
	std::vector<uint8_t> storage;
};

EXPORT int SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(void *, int channel, void **out, int max)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	Poll();
	auto &queue = g_channels[channel];
	int n = 0;
	while (n < max && !queue.empty())
	{
		auto *msg = new MockMessage();
		msg->storage = std::move(queue.front().data);
		msg->data = msg->storage.data();
		msg->size = static_cast<int32_t>(msg->storage.size());
		SetIdentity(msg->identity, queue.front().sender);
		queue.pop_front();
		out[n++] = msg;
	}
	return n;
}

EXPORT void SteamAPI_SteamNetworkingMessage_t_Release(void *msg)
{
	delete static_cast<MockMessage *>(msg);
}

EXPORT bool SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(void *, const void *identity)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	const uint64_t id = GetIdentity(identity);
	g_accepted.insert(id);
	for (auto it = g_held.begin(); it != g_held.end();)
	{
		if (it->sender == id)
		{
			g_channels[it->channel].push_back(std::move(*it));
			it = g_held.erase(it);
		}
		else
		{
			++it;
		}
	}
	return true;
}

EXPORT bool SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser(void *, const void *identity)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	const uint64_t id = GetIdentity(identity);
	g_accepted.erase(id);
	g_requested.erase(id);
	return true;
}
