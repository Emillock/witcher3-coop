// Standalone C++17 test: g++ -std=c++17 tests/test_relay_xml.cpp -o test_relay_xml
#include "../relay/xml_config.h"

#include <cassert>
#include <string>

int main()
{
	const std::string initial = "<Config><Username>Player</Username><Port>40000</Port></Config>";
	std::string xml = initial;
	w3coop::ReplaceUsername(xml, "Geralt");
	assert(xml == "<Config><Username>Geralt</Username><Port>40000</Port></Config>");

	xml = initial;
	w3coop::ReplaceUsername(xml, "A&B <C> \"D\" 'E'");
	assert(xml == "<Config><Username>A&amp;B &lt;C&gt; &quot;D&quot; &apos;E&apos;</Username><Port>40000</Port></Config>");

	xml = initial;
	w3coop::ReplaceUsername(xml, "$&-$1-\\test");
	assert(xml == "<Config><Username>$&amp;-$1-\\test</Username><Port>40000</Port></Config>");

	xml = initial;
	w3coop::ReplaceUsername(xml, "");
	assert(xml == initial);

	xml = "<Config><Port>40000</Port></Config>";
	w3coop::ReplaceUsername(xml, "Geralt");
	assert(xml == "<Config><Port>40000</Port></Config>");
}
