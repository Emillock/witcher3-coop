// Standalone C++17 test: g++ -std=c++17 tests/test_port_arg.cpp -o test_port_arg
#include "../relay/port_arg.h"

#include <cassert>
#include <cstdint>
#include <initializer_list>

int main()
{
	uint16_t port = 1234;
	assert(w3coop::ParseUdpPort(L"1", port) && port == 1);
	assert(w3coop::ParseUdpPort(L"40000", port) && port == 40000);
	assert(w3coop::ParseUdpPort(L"65535", port) && port == 65535);
	assert(w3coop::ParseUdpPort(L"00080", port) && port == 80);

	for (const wchar_t *invalid : {L"", L"0", L"00000", L"65536", L"99999", L"99999999999999999999",
	                               L"-1", L"+80", L"80junk", L" 80", L"80 ", L"a", L"１２３"})
	{
		port = 1234;
		assert(!w3coop::ParseUdpPort(invalid, port));
		assert(port == 1234);
	}
}
