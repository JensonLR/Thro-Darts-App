package thro.client

// Where the Android app finds THRØ's public web site (PD-094, PD-097).
//
// **Kept by `tools/host.py` with every other place that names a host**, the way `THROWebBaseURL` is on the iPhone, so
// the domain switch moves it with them. Change it with the script, not by hand: `python3 tools/host.py` fails CI when
// this disagrees with the rest.

/** The public web site: a static site, which answers whatever the API is doing. The notice is read from here. */
public const val THRO_WEB_BASE_URL: String = "https://thro.uk"
