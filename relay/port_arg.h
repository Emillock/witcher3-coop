#pragma once

#include <cstdint>
#include <string_view>

namespace w3coop
{
	inline bool ParseUdpPort(std::wstring_view text, uint16_t &port)
	{
		if (text.empty())
			return false;

		uint32_t value = 0;
		for (wchar_t digit : text)
		{
			if (digit < L'0' || digit > L'9')
				return false;
			value = value * 10 + static_cast<uint32_t>(digit - L'0');
			if (value > 65535)
				return false;
		}
		if (value == 0)
			return false;

		port = static_cast<uint16_t>(value);
		return true;
	}
}
