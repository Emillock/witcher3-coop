#pragma once

#include <regex>
#include <string>
#include <string_view>

namespace w3coop
{
	inline std::string EscapeXmlText(std::string_view text)
	{
		std::string escaped;
		escaped.reserve(text.size());
		for (char c : text)
		{
			switch (c)
			{
			case '&': escaped += "&amp;"; break;
			case '<': escaped += "&lt;"; break;
			case '>': escaped += "&gt;"; break;
			case '"': escaped += "&quot;"; break;
			case '\'': escaped += "&apos;"; break;
			default: escaped += c; break;
			}
		}
		return escaped;
	}

	inline void ReplaceUsername(std::string &xml, std::string_view username)
	{
		if (username.empty())
			return;
		const std::regex tag("<Username>[^<]*</Username>");
		std::smatch match;
		if (std::regex_search(xml, match, tag))
		{
			// Direct replacement avoids treating '$' in usernames as regex replacement tokens.
			xml.replace(static_cast<size_t>(match.position()), static_cast<size_t>(match.length()),
			            "<Username>" + EscapeXmlText(username) + "</Username>");
		}
	}
}
