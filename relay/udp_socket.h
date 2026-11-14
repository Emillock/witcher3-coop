#pragma once

#include <winsock2.h>
#include <windows.h>

#include <cstdint>
#include <cstdio>

namespace w3coop
{
	inline SOCKET UdpSocket(uint16_t bindPort, const sockaddr_in *remote = nullptr)
	{
		SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
		if (s == INVALID_SOCKET)
		{
			printf("Could not create UDP socket (Winsock error %d).\n", WSAGetLastError());
			return INVALID_SOCKET;
		}
		sockaddr_in addr{};
		addr.sin_family = AF_INET;
		addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
		addr.sin_port = htons(bindPort);
		if (bind(s, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) == SOCKET_ERROR)
		{
			printf("Could not bind UDP port %u (Winsock error %d).\n", static_cast<unsigned>(bindPort), WSAGetLastError());
			closesocket(s);
			return INVALID_SOCKET;
		}
		u_long nonBlocking = 1;
		if (ioctlsocket(s, FIONBIO, &nonBlocking) == SOCKET_ERROR)
		{
			printf("Could not set UDP socket nonblocking (Winsock error %d).\n", WSAGetLastError());
			closesocket(s);
			return INVALID_SOCKET;
		}
		// a previous peer port being closed must not kill the socket (WSAECONNRESET on UDP)
		BOOL off = FALSE;
		DWORD ignored = 0;
		WSAIoctl(s, _WSAIOW(IOC_VENDOR, 12), &off, sizeof(off), nullptr, 0, &ignored, nullptr, nullptr);
		if (remote && connect(s, reinterpret_cast<const sockaddr *>(remote), sizeof(*remote)) == SOCKET_ERROR)
		{
			printf("Could not connect UDP socket to server (Winsock error %d).\n", WSAGetLastError());
			closesocket(s);
			return INVALID_SOCKET;
		}
		return s;
	}
}
