from __future__ import annotations

"""Wireless-client discovery shared by modern ACP and legacy SNMP devices."""

import ipaddress
import re
import socket
import subprocess
import time
from urllib.parse import unquote
from concurrent.futures import ThreadPoolExecutor, wait
from typing import Any, Callable, Iterable

from backend.cfb0 import CFB0Integer


APPLE_BASE_STATION_3_MIB = "1.3.6.1.4.1.63.501.3"
WIRELESS_PHYS_ADDRESS_OID = APPLE_BASE_STATION_3_MIB + ".2.2.1.1"
WIRELESS_TYPE_OID = APPLE_BASE_STATION_3_MIB + ".2.2.1.2"
WIRELESS_DATA_RATES_OID = APPLE_BASE_STATION_3_MIB + ".2.2.1.3"
WIRELESS_LAST_REFRESH_OID = APPLE_BASE_STATION_3_MIB + ".2.2.1.5"
WIRELESS_STRENGTH_OID = APPLE_BASE_STATION_3_MIB + ".2.2.1.6"
WIRELESS_NOISE_OID = APPLE_BASE_STATION_3_MIB + ".2.2.1.7"
WIRELESS_RATE_OID = APPLE_BASE_STATION_3_MIB + ".2.2.1.8"
DHCP_PHYS_ADDRESS_OID = APPLE_BASE_STATION_3_MIB + ".3.2.1.1"
DHCP_IP_ADDRESS_OID = APPLE_BASE_STATION_3_MIB + ".3.2.1.2"

_MAC_PATTERN = re.compile(
    r"(?i)(?<![0-9a-f])(?:[0-9a-f]{1,2}[:-]){5}[0-9a-f]{1,2}(?![0-9a-f])"
)
_ARP_PATTERN = re.compile(
    r"\((?P<ip>[^)]+)\)\s+at\s+(?P<mac>(?:[0-9a-f]{1,2}:){5}[0-9a-f]{1,2})\b",
    re.IGNORECASE,
)
_NDP_PATTERN = re.compile(
    r"^(?P<ip>\S+)\s+(?P<mac>(?:[0-9a-f]{1,2}:){5}[0-9a-f]{1,2})\b",
    re.IGNORECASE,
)
_IPV4_PATTERN = re.compile(
    r"(?<!\d)(?:25[0-5]|2[0-4]\d|1?\d?\d)"
    r"(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?!\d)"
)
_HOSTNAME_LOOKUP_BUDGET_SECONDS = 1.0
_HOSTNAME_LOOKUP_MAX_WORKERS = 8
_NEIGHBOR_DISCOVERY_PREFIX_LENGTH = 24
_NEIGHBOR_DISCOVERY_MAX_WORKERS = 48
_NEIGHBOR_DISCOVERY_PING_WAIT_MILLISECONDS = 250
_NEIGHBOR_DISCOVERY_PROCESS_TIMEOUT_SECONDS = 0.75


def normalize_mac(value: Any) -> str | None:
    """Return a canonical uppercase MAC address, or ``None``."""

    if isinstance(value, (bytes, bytearray)) and len(value) == 6:
        octets = list(value)
    elif isinstance(value, str):
        match = _MAC_PATTERN.search(value.strip())
        if match is not None:
            parts = re.split(r"[:-]", match.group(0))
        else:
            compact = re.sub(r"[^0-9a-f]", "", value, flags=re.IGNORECASE)
            if len(compact) != 12:
                return None
            parts = [compact[index:index + 2] for index in range(0, 12, 2)]
        try:
            octets = [int(part, 16) for part in parts]
        except ValueError:
            return None
    else:
        return None
    if len(octets) != 6 or any(not 0 <= octet <= 255 for octet in octets):
        return None
    return ":".join(f"{octet:02X}" for octet in octets)


def _append_unique_mac(macs: list[str], value: Any) -> None:
    mac = normalize_mac(value)
    if mac is not None and mac not in macs:
        macs.append(mac)


def _signed_cfb0_integer(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        number = int(value)
    except (TypeError, ValueError, OverflowError):
        return None
    width = value.width if isinstance(value, CFB0Integer) else None
    if width is not None and width > 0:
        sign_bit = 1 << (width * 8 - 1)
        if number >= sign_bit:
            number -= 1 << (width * 8)
    elif (1 << 63) <= number < (1 << 64):
        # Trace fixtures and callers may provide the decoded unsigned integer
        # without retaining CFB0Integer's source width.
        number -= 1 << 64
    return number


def _optional_metric(value: Any, *, signed: bool = False) -> int | float | None:
    if value is None or isinstance(value, bool):
        return None
    number: int | float | None
    if signed:
        number = _signed_cfb0_integer(value)
    elif isinstance(value, (int, float)):
        number = int(value) if isinstance(value, int) else float(value)
    else:
        try:
            number = float(str(value).strip())
        except (TypeError, ValueError):
            return None
    if number == -1:
        return None
    return number


def _first_metric(
    values: dict[str, Any],
    keys: tuple[str, ...],
    *,
    signed: bool = False,
) -> int | float | None:
    for key in keys:
        metric = _optional_metric(values.get(key), signed=signed)
        if metric is not None:
            return metric
    return None


def _wireless_interfaces(system_interfaces_response: Any) -> list[dict[str, Any]]:
    interfaces = system_interfaces_response
    for key in ("outputs", "data", "LAN", "interfaces"):
        if not isinstance(interfaces, dict):
            return []
        interfaces = interfaces.get(key, [])
    if not isinstance(interfaces, list):
        return []
    return [
        interface
        for interface in interfaces
        if isinstance(interface, dict)
        and (
            "802.11" in str(interface.get("type", "")).lower()
            or "wireless" in str(interface.get("type", "")).lower()
        )
    ]


def modern_wireless_client_details(
    radio_station_list: Any,
    system_interfaces_response: Any,
) -> tuple[list[str], dict[str, dict[str, Any]]]:
    """Extract associated stations and cached connection telemetry by MAC."""

    macs: list[str] = []
    details_by_mac: dict[str, dict[str, Any]] = {}
    if isinstance(radio_station_list, dict):
        for stations in radio_station_list.values():
            if not isinstance(stations, list):
                continue
            for station in stations:
                if not isinstance(station, dict):
                    continue
                opmode = str(station.get("opmode", "sta")).strip().lower()
                if opmode != "sta":
                    continue
                mac = normalize_mac(
                    station.get("macAddress", station.get("MAC"))
                )
                if mac is None:
                    continue
                _append_unique_mac(macs, mac)
                details = details_by_mac.setdefault(mac, {})
                rssi = _first_metric(
                    station,
                    ("rssi_local", "rssi"),
                    signed=True,
                )
                rate = _first_metric(
                    station,
                    ("txrate_local", "txrate"),
                )
                noise = _optional_metric(station.get("noise"), signed=True)
                phy_mode = str(station.get("phy_mode", "")).strip()
                if rssi is not None:
                    details["rssi"] = int(rssi)
                if rate is not None and rate >= 0:
                    details["dataRateMbps"] = rate
                if noise is not None:
                    details["noise"] = int(noise)
                if phy_mode:
                    details["phyMode"] = phy_mode

    for interface in _wireless_interfaces(system_interfaces_response):
        clients = interface.get("clients", [])
        if not isinstance(clients, list):
            continue
        for client in clients:
            if isinstance(client, dict):
                mac = normalize_mac(
                    client.get("MAC", client.get("macAddress"))
                )
                phy_mode = str(
                    client.get("PHY", client.get("phy_mode", ""))
                ).strip()
            else:
                mac = normalize_mac(client)
                phy_mode = ""
            if mac is None:
                continue
            _append_unique_mac(macs, mac)
            details = details_by_mac.setdefault(mac, {})
            if phy_mode and not details.get("phyMode"):
                details["phyMode"] = phy_mode
    return macs, details_by_mac


def modern_wireless_macs(
    radio_station_list: Any,
    system_interfaces_response: Any,
) -> list[str]:
    """Extract wireless station MACs while excluding Ethernet bridge caches."""

    macs, _ = modern_wireless_client_details(
        radio_station_list, system_interfaces_response
    )
    return macs


def _numeric_oid(text: str) -> str | None:
    token = text.strip().split(maxsplit=1)[0].lstrip(".")
    return token if token and all(part.isdigit() for part in token.split(".")) else None


def _snmp_value(line: str) -> str:
    parts = line.strip().split(maxsplit=1)
    if len(parts) < 2:
        return ""
    value = parts[1].strip()
    if value.startswith("="):
        value = value[1:].strip()
    if ":" in value:
        kind, candidate = value.split(":", 1)
        if kind.strip().replace("-", " ").replace("_", " ").isupper():
            value = candidate.strip()
    return value.strip().strip('"')


def _mac_from_oid_index(oid: str, column_oid: str) -> str | None:
    prefix = column_oid + "."
    if not oid.startswith(prefix):
        return None
    try:
        suffix = [int(part) for part in oid[len(prefix):].split(".")]
    except ValueError:
        return None
    # PhysAddress is an OCTET STRING index and normally carries a leading
    # length component. Accept an implied six-octet index as well.
    if len(suffix) >= 7 and suffix[-7] == 6:
        suffix = suffix[-6:]
    elif len(suffix) >= 6:
        suffix = suffix[-6:]
    else:
        return None
    if any(not 0 <= octet <= 255 for octet in suffix):
        return None
    return normalize_mac(bytes(suffix))


def parse_legacy_snmp_client_details(
    output: str,
) -> tuple[list[str], dict[str, str], dict[str, dict[str, Any]]]:
    """Return legacy station identities, DHCP addresses, and telemetry."""

    wireless_order: list[str] = []
    wireless_types: dict[str, int] = {}
    dhcp_addresses: dict[str, str] = {}
    details_by_mac: dict[str, dict[str, Any]] = {}

    for line in output.splitlines():
        oid = _numeric_oid(line)
        if oid is None:
            continue
        value = _snmp_value(line)

        mac = _mac_from_oid_index(oid, WIRELESS_PHYS_ADDRESS_OID)
        if mac is not None:
            _append_unique_mac(wireless_order, mac)
            continue

        mac = _mac_from_oid_index(oid, WIRELESS_TYPE_OID)
        if mac is not None:
            match = re.search(r"-?\d+", value)
            if match is not None:
                wireless_types[mac] = int(match.group(0))
            continue

        for column_oid, field in (
            (WIRELESS_LAST_REFRESH_OID, "statisticsAgeSeconds"),
            (WIRELESS_STRENGTH_OID, "rssi"),
            (WIRELESS_NOISE_OID, "noise"),
            (WIRELESS_RATE_OID, "dataRateMbps"),
        ):
            mac = _mac_from_oid_index(oid, column_oid)
            if mac is None:
                continue
            match = re.search(r"-?\d+(?:\.\d+)?", value)
            if match is not None:
                parsed = _optional_metric(match.group(0), signed=field != "dataRateMbps")
                if parsed is not None:
                    details_by_mac.setdefault(mac, {})[field] = parsed
            break
        else:
            mac = None
        if mac is not None:
            continue

        # The available-rate string is not a negotiated PHY mode, but retain
        # it in the backend record for diagnostics and future trace matching.
        mac = _mac_from_oid_index(oid, WIRELESS_DATA_RATES_OID)
        if mac is not None:
            if value:
                details_by_mac.setdefault(mac, {})["supportedDataRates"] = value
            continue

        mac = _mac_from_oid_index(oid, DHCP_IP_ADDRESS_OID)
        if mac is not None:
            match = _IPV4_PATTERN.search(value)
            if match is not None:
                dhcp_addresses[mac] = match.group(0)
            continue

        # Some net-snmp output formats make the value easier to consume than
        # the OCTET STRING index. Record the DHCP row's MAC column so later
        # columns can still be correlated through their shared index.
        mac = _mac_from_oid_index(oid, DHCP_PHYS_ADDRESS_OID)
        if mac is not None:
            continue

    # Type 1 is a station; type 2 is a WDS peer. Include a row when an older
    # agent omits the type column, but never expose a confirmed WDS node.
    wireless_order = [
        mac for mac in wireless_order if wireless_types.get(mac, 1) == 1
    ]
    station_set = set(wireless_order)
    details_by_mac = {
        mac: details
        for mac, details in details_by_mac.items()
        if mac in station_set
    }
    return wireless_order, dhcp_addresses, details_by_mac


def parse_legacy_snmp_walk(output: str) -> tuple[list[str], dict[str, str]]:
    """Return associated STA MACs and DHCP IPv4 addresses keyed by MAC."""

    macs, dhcp_addresses, _ = parse_legacy_snmp_client_details(output)
    return macs, dhcp_addresses


def run_legacy_snmp_walk(
    host: str,
    community: str,
    *,
    run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> str:
    result = run(
        [
            "/usr/bin/snmpwalk",
            "-v",
            "2c",
            "-On",
            "-OQ",
            "-t",
            "2",
            "-r",
            "1",
            "-c",
            community,
            host,
            APPLE_BASE_STATION_3_MIB,
        ],
        capture_output=True,
        text=True,
        errors="replace",
        timeout=8,
        check=False,
    )
    if result.returncode:
        message = result.stderr.strip() or result.stdout.strip() or "SNMP walk failed"
        raise RuntimeError(message)
    output = result.stdout.strip()
    lowered = output.lower()
    if (
        not output
        or lowered.startswith("timeout")
        or lowered.startswith("no such object")
        or "no such object available" in lowered
        or lowered.startswith("no hostname specified")
        or lowered.startswith("error")
    ):
        raise RuntimeError(output or "SNMP walk returned no data")
    return result.stdout


def read_neighbor_cache(
    *,
    run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> dict[str, list[str]]:
    """Read the Mac's existing ARP/NDP mappings without scanning the subnet."""

    mappings: dict[str, list[str]] = {}
    commands = [
        (["/usr/sbin/arp", "-an"], _ARP_PATTERN),
        (["/usr/sbin/ndp", "-an"], _NDP_PATTERN),
    ]
    for command, pattern in commands:
        try:
            result = run(
                command,
                capture_output=True,
                text=True,
                timeout=2,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode:
            continue
        for line in result.stdout.splitlines():
            match = pattern.search(line)
            if match is None:
                continue
            mac = normalize_mac(match.group("mac"))
            raw_ip = match.group("ip").split("%", 1)[0]
            try:
                ip = str(ipaddress.ip_address(raw_ip))
            except ValueError:
                continue
            if mac is not None and ip not in mappings.setdefault(mac, []):
                mappings[mac].append(ip)
    return mappings


def _resolved_private_ipv4(
    host: str,
    *,
    getaddrinfo: Callable[..., list[tuple[Any, ...]]] = socket.getaddrinfo,
) -> ipaddress.IPv4Address | None:
    normalized_host = host.strip().strip("[]")
    try:
        address = ipaddress.ip_address(normalized_host)
    except ValueError:
        try:
            results = getaddrinfo(
                normalized_host,
                None,
                socket.AF_INET,
                socket.SOCK_DGRAM,
            )
        except OSError:
            return None
        address = next(
            (
                ipaddress.ip_address(result[4][0])
                for result in results
                if len(result) >= 5 and result[4]
            ),
            None,
        )
    if not isinstance(address, ipaddress.IPv4Address):
        return None
    if not (address.is_private or address.is_link_local):
        return None
    return address


_LOCAL_INTERFACE_PATTERN = re.compile(
    r"inet\s+(?P<ip>\d+\.\d+\.\d+\.\d+)\s+(?:-->\s+\S+\s+)?netmask\s+0x(?P<mask>[0-9a-fA-F]{8})"
)


def read_local_ipv4_networks(
    *,
    run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> list[ipaddress.IPv4Network]:
    """Read this Mac's own local IPv4 interface subnets, loopback excluded.

    Parsed from ``ifconfig`` (no third-party dependency) rather than a
    higher-level API, matching the parsing approach already used for
    ``arp -an``/``ndp -an`` above.
    """

    try:
        result = run(
            ["/sbin/ifconfig"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if result.returncode:
        return []
    networks: list[ipaddress.IPv4Network] = []
    for match in _LOCAL_INTERFACE_PATTERN.finditer(result.stdout):
        try:
            address = ipaddress.ip_address(match.group("ip"))
        except ValueError:
            continue
        if not isinstance(address, ipaddress.IPv4Address) or address.is_loopback:
            continue
        prefix_length = bin(int(match.group("mask"), 16)).count("1")
        try:
            networks.append(
                ipaddress.ip_network(f"{address}/{prefix_length}", strict=False)
            )
        except ValueError:
            continue
    return networks


def _is_on_a_local_network(
    address: ipaddress.IPv4Address, networks: Iterable[ipaddress.IPv4Network]
) -> bool:
    return any(address in network for network in networks)


def local_network_mismatch_note(
    host: str,
    *,
    getaddrinfo: Callable[..., list[tuple[Any, ...]]] = socket.getaddrinfo,
    read_local_networks: Callable[
        [], list[ipaddress.IPv4Network]
    ] = read_local_ipv4_networks,
) -> str | None:
    """A user-facing note when the base station isn't on this Mac's own network.

    Returns ``None`` in the normal case (the base station's address is on
    one of this Mac's local networks, or didn't resolve to a private address
    at all - a different, unrelated situation). Otherwise returns text
    explaining why client IP addresses and hostnames can't be resolved right
    now, without assuming a specific cause (VPN, remote access, or a genuine
    double-NAT all produce this same, correctly-reported condition).
    """

    address = _resolved_private_ipv4(host, getaddrinfo=getaddrinfo)
    if address is None:
        return None
    if _is_on_a_local_network(address, read_local_networks()):
        return None
    return (
        f"This Mac isn't on the same local network as the base station ({address}), "
        "so connected clients' IP addresses and hostnames can't be resolved. This is "
        "expected when connecting over a VPN or other remote access, or across a "
        "double-NAT boundary."
    )


def discover_neighbor_cache(
    host: str,
    *,
    getaddrinfo: Callable[..., list[tuple[Any, ...]]] = socket.getaddrinfo,
    run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    read_cache: Callable[[], dict[str, list[str]]] = read_neighbor_cache,
    read_local_networks: Callable[
        [], list[ipaddress.IPv4Network]
    ] = read_local_ipv4_networks,
    max_workers: int = _NEIGHBOR_DISCOVERY_MAX_WORKERS,
    diagnostic: Callable[[str], None] | None = None,
) -> dict[str, list[str]]:
    """Prime the local /24 neighbour table before correlating clients by MAC.

    AirPorts in bridge mode know a station's MAC address but do not own the
    upstream DHCP lease that maps it to an IP address. Bounded concurrent ICMP
    probes ask macOS to resolve reachable local peers into ARP without opening
    an application session.
    """

    before = read_cache()
    address = _resolved_private_ipv4(host, getaddrinfo=getaddrinfo)
    if address is None:
        if diagnostic is not None:
            diagnostic(
                f"base station {host!r} did not resolve to a private IPv4 address; "
                f"sweep skipped; neighbor mappings before={_mapping_count(before)}"
            )
        return before
    local_networks = read_local_networks()
    if not _is_on_a_local_network(address, local_networks):
        if diagnostic is not None:
            local_summary = ", ".join(str(network) for network in local_networks)
            diagnostic(
                f"base station address={address} is not on any of this Mac's local "
                f"networks ({local_summary or 'none detected'}); IP/hostname discovery "
                "requires sharing a local network segment with the base station, which "
                "is not possible over a VPN/remote-access connection or across a "
                "double-NAT boundary; sweep skipped; "
                f"neighbor mappings before={_mapping_count(before)}"
            )
        return before
    network = ipaddress.ip_network(
        f"{address}/{_NEIGHBOR_DISCOVERY_PREFIX_LENGTH}",
        strict=False,
    )
    if diagnostic is not None:
        diagnostic(
            f"base station address={address}; selected subnet={network}; "
            f"neighbor mappings before={_mapping_count(before)}"
        )

    def ping(candidate: ipaddress.IPv4Address) -> bool:
        try:
            result = run(
                [
                    "/sbin/ping",
                    "-n",
                    "-q",
                    "-c",
                    "1",
                    "-W",
                    str(_NEIGHBOR_DISCOVERY_PING_WAIT_MILLISECONDS),
                    str(candidate),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=_NEIGHBOR_DISCOVERY_PROCESS_TIMEOUT_SECONDS,
                check=False,
            )
            return result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    candidates = list(network.hosts())
    started = time.monotonic()
    with ThreadPoolExecutor(
        max_workers=max(1, min(max_workers, len(candidates)))
    ) as executor:
        responses = sum(executor.map(ping, candidates))
    elapsed = time.monotonic() - started
    after = read_cache()
    if diagnostic is not None:
        diagnostic(
            f"reachability sweep duration={elapsed:.3f}s; "
            f"responsive hosts={responses}/{len(candidates)}; "
            f"neighbor mappings after={_mapping_count(after)}"
        )
    return after


def _mapping_count(mappings: dict[str, list[str]]) -> int:
    return sum(len(addresses) for addresses in mappings.values())


def reverse_hostname(
    ip: str,
    *,
    run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> str:
    """Perform a bounded Directory Services reverse lookup, including mDNS."""

    try:
        result = run(
            ["/usr/bin/dscacheutil", "-q", "host", "-a", "ip_address", ip],
            capture_output=True,
            text=True,
            timeout=1,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode:
        return ""
    for line in result.stdout.splitlines():
        key, separator, value = line.partition(":")
        if separator and key.strip().lower() == "name":
            hostname = value.strip().rstrip(".")
            if hostname and hostname != ip:
                return hostname
    return ""


def smb_hostname(
    ip: str,
    *,
    run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> str:
    """Return a Windows or Samba system name advertised through NetBIOS."""

    try:
        result = run(
            ["/usr/bin/smbutil", "status", "-a", ip],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=1,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode:
        return ""
    for line in result.stdout.splitlines():
        key, separator, value = line.partition(":")
        if separator and key.strip().lower() == "server":
            hostname = unquote(value.strip()).rstrip(".")
            if hostname and hostname != ip:
                return hostname
    for line in result.stdout.splitlines():
        match = re.match(
            r"^\s*([^\s<]+)\s+<00>\s+-\s+(?!<GROUP>)",
            line,
            re.IGNORECASE,
        )
        if match is not None:
            return unquote(match.group(1)).rstrip(".")
    return ""


def cross_platform_hostname(
    ip: str,
    *,
    reverse_lookup: Callable[[str], str] | None = None,
    smb_lookup: Callable[[str], str] | None = None,
) -> str:
    """Resolve DNS/mDNS first, then Windows and Samba naming."""

    reverse_lookup = reverse_lookup or reverse_hostname
    smb_lookup = smb_lookup or smb_hostname
    return reverse_lookup(ip) or smb_lookup(ip)


def diagnostic_hostname(
    ip: str,
    *,
    diagnostic: Callable[[str], None],
    reverse_lookup: Callable[[str], str] | None = None,
    smb_lookup: Callable[[str], str] | None = None,
) -> str:
    """Resolve a host while reporting every attempted source."""

    reverse_lookup = reverse_lookup or reverse_hostname
    smb_lookup = smb_lookup or smb_hostname
    diagnostic(f"resolver reverse DNS/mDNS attempted for {ip}")
    hostname = reverse_lookup(ip)
    if hostname:
        diagnostic(f"resolved {ip} name={hostname!r} source=reverse DNS/mDNS")
        return hostname
    diagnostic(f"resolver SMB/NetBIOS attempted for {ip}")
    hostname = smb_lookup(ip)
    if hostname:
        diagnostic(f"resolved {ip} name={hostname!r} source=SMB/NetBIOS")
        return hostname
    diagnostic(f"resolved {ip} name unavailable; source=none")
    return ""


def resolved_client_records(
    macs: Iterable[str],
    *,
    addresses_by_mac: dict[str, str] | None = None,
    neighbor_addresses: dict[str, list[str]] | None = None,
    details_by_mac: dict[str, dict[str, Any]] | None = None,
    hostname_lookup: Callable[[str], str] | None = None,
    hostname_lookup_budget_seconds: float = _HOSTNAME_LOOKUP_BUDGET_SECONDS,
    hostname_lookup_max_workers: int = _HOSTNAME_LOOKUP_MAX_WORKERS,
    diagnostic: Callable[[str], None] | None = None,
) -> list[dict[str, Any]]:
    """Resolve associated stations while retaining MAC-only associations."""

    addresses_by_mac = addresses_by_mac or {}
    neighbor_addresses = neighbor_addresses or {}
    details_by_mac = details_by_mac or {}
    hostname_lookup = hostname_lookup or cross_platform_hostname
    records: list[dict[str, Any]] = []
    for raw_mac in macs:
        mac = normalize_mac(raw_mac)
        if mac is None:
            continue
        candidates: list[str] = []
        device_ip = addresses_by_mac.get(mac, "")
        if device_ip:
            candidates.append(device_ip)
        for ip in neighbor_addresses.get(mac, []):
            if ip not in candidates:
                candidates.append(ip)
        if not candidates:
            if diagnostic is not None:
                diagnostic(f"exact MAC match {mac}: no IP mapping")
            records.append(
                {
                    "macAddress": mac,
                    "ipAddress": "",
                    "hostname": "",
                }
            )
            records[-1].update(details_by_mac.get(mac, {}))
            continue
        # Prefer IPv4, as AirPort Utility does when both address families are
        # available, while retaining IPv6 as a fallback.
        def address_preference(candidate: str) -> tuple[int, int]:
            address = ipaddress.ip_address(candidate)
            return (
                0 if address.version == 4 else 1,
                1 if address.is_link_local else 0,
            )

        candidates.sort(key=address_preference)
        ip = candidates[0]
        if diagnostic is not None:
            diagnostic(f"exact MAC match {mac}: IP={ip}")
        records.append(
            {
                "macAddress": mac,
                "ipAddress": ip,
                "hostname": "",
            }
        )
        records[-1].update(details_by_mac.get(mac, {}))

    ips = list(
        dict.fromkeys(
            record["ipAddress"] for record in records if record["ipAddress"]
        )
    )
    if not ips or hostname_lookup_budget_seconds <= 0:
        return records

    executor = ThreadPoolExecutor(
        max_workers=max(1, min(hostname_lookup_max_workers, len(ips)))
    )
    def lookup(ip: str) -> str:
        if diagnostic is not None and hostname_lookup is cross_platform_hostname:
            return diagnostic_hostname(ip, diagnostic=diagnostic)
        return hostname_lookup(ip)

    futures = {executor.submit(lookup, ip): ip for ip in ips}
    try:
        completed, pending = wait(
            futures,
            timeout=hostname_lookup_budget_seconds,
        )
        hostnames: dict[str, str] = {}
        for future in completed:
            try:
                hostname = future.result()
            except Exception:
                continue
            if isinstance(hostname, str) and hostname:
                hostnames[futures[future]] = hostname
        for future in pending:
            future.cancel()
            if diagnostic is not None:
                diagnostic(f"resolver budget expired for {futures[future]}")
    finally:
        # Each production lookup also has its own one-second subprocess
        # timeout. Do not make the caller wait serially for unfinished lookups
        # after the shared budget expires.
        executor.shutdown(wait=False, cancel_futures=True)

    for record in records:
        record["hostname"] = hostnames.get(record["ipAddress"], "")
    return records
