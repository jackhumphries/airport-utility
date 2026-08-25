# Wi-Fi congestion analysis

The Dashboard can perform an on-demand scan of nearby Wi-Fi networks and
offer advisory channel recommendations. The scan is read-only: it never changes
the AirPort configuration, and it does not run continuously or at launch.

## Method

The app uses macOS CoreWLAN to collect the channel and received signal strength
of networks visible to the Mac. Network names and hardware addresses are not
stored. The latest aggregate result may be included in an exported diagnostics
bundle, but it contains only band, channel, count, condition, and summary data.
For 2.4 GHz, the analyser compares the non-overlapping channels 1, 6,
and 11 and weights nearby overlapping channels by signal strength. For 5 GHz,
it compares common non-DFS channels that macOS reports as permitted for the
current interface. A recommendation is made only when the best candidate has a
materially lower observed contention score; otherwise the current channel is
described as competitive.

## Limits and permissions

The result describes conditions at the Mac, not necessarily at the AirPort or
every client. Hidden networks, intermittent transmitters, DFS channels, channel
width, non-Wi-Fi interference, and networks outside the scan window can affect
real performance. macOS may require Location Services permission before it
exposes nearby Wi-Fi information. If the scan cannot run, the app reports it as
unavailable rather than guessing.

Channel recommendations are guidance only. Changing a channel remains a normal
configuration operation with the existing preview and confirmation safeguards.
