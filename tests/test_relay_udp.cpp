// The socket helper tests run on Windows without Steam or the game.
#include "../relay/udp_socket.h"

#include <cassert>

#pragma comment(lib, "ws2_32.lib")

int main()
{
	// socket() fails before Winsock is initialized.
	assert(w3coop::UdpSocket(0) == INVALID_SOCKET);
	WSADATA wsa{};
	assert(WSAStartup(MAKEWORD(2, 2), &wsa) == 0);

	const SOCKET receiver = w3coop::UdpSocket(0);
	assert(receiver != INVALID_SOCKET);
	sockaddr_in address{};
	int length = sizeof(address);
	assert(getsockname(receiver, reinterpret_cast<sockaddr *>(&address), &length) == 0);
	assert(address.sin_port != 0);
	assert(w3coop::UdpSocket(ntohs(address.sin_port)) == INVALID_SOCKET);

	// Receiving on a fresh socket must not block the relay's event loop.
	char data[8];
	assert(recv(receiver, data, sizeof(data), 0) == SOCKET_ERROR);
	assert(WSAGetLastError() == WSAEWOULDBLOCK);

	sockaddr_in invalid = address;
	invalid.sin_family = 0xffff;
	assert(w3coop::UdpSocket(0, &invalid) == INVALID_SOCKET);

	const SOCKET sender = w3coop::UdpSocket(0, &address);
	assert(sender != INVALID_SOCKET);
	assert(send(sender, "hello", 5, 0) == 5);
	fd_set ready;
	FD_ZERO(&ready);
	FD_SET(receiver, &ready);
	timeval timeout{1, 0};
	assert(select(0, &ready, nullptr, nullptr, &timeout) == 1);
	assert(recv(receiver, data, sizeof(data), 0) == 5);
	assert(data[0] == 'h' && data[4] == 'o');

	closesocket(sender);
	closesocket(receiver);
	WSACleanup();
}
