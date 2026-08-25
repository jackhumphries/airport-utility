#!/usr/bin/env python3
from __future__ import annotations

"""AirPort/Time Capsule ACP command-line backend.

The Swift app shells out to this module for both modern and legacy base station
workflows. It can read individual ACP settings, batch-read profile data, write
dirty setting dictionaries, produce dry-run JSON intents, upload firmware,
invoke disk erase/archive actions, and reboot devices after configuration or
firmware changes.

Modern AirPort devices use Apple's AirPort Configuration Protocol (ACP) over
TCP port 5009. Authentication starts with cleartext CFB0 dictionaries carrying
an AppleSRP-compatible SRP-6a exchange; successful authentication derives
independent AES stream keys for encrypted property reads, RPC calls, and
property writes. Legacy 802.11g-era devices use the older static-key ACP header
path implemented near the end of this file.

Protocol helpers now live under ``backend`` modules for ACP transport, CFB0,
SRP, modern reads, legacy framing, firmware helpers, and disk selection. This
wrapper still owns CLI parsing plus the remaining modern write, firmware upload
session, disk RPC orchestration, and legacy argument-mapping flow.
"""

import argparse
import inspect
import json
from pathlib import Path
import struct
import sys
import time
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend.acp import ACPEncryptedTransport
from backend.acp import ACPHeader
from backend.acp import ACPStreamCipher
from backend.acp import ACPPlainTransport
from backend.acp import ACP_HEADER_LEN
from backend.acp import ACP_MAGIC
from backend.acp import ACP_MAX_BODY_SIZE
from backend.acp import ACP_PORT
from backend.acp import ACP_PROPERTY_HEADER
from backend.acp import ACP_REQUEST_SALT
from backend.acp import ACP_RESPONSE_SALT
from backend.acp import ACP_STREAM_SIZE
from backend.acp import CommonCryptoAES
from backend.acp import DEFAULT_CLIENT_TOKEN
from backend.acp import acp_adler32
from backend.acp import connect_acp
from backend.acp import make_header
from backend.acp import parse_header
from backend.acp import recvn
from backend.srp import AuthResult
from backend.srp import SRPValues
from backend.srp import applesrp_client_proof
from backend.srp import authenticate
from backend.srp import derive_keys
from backend.srp import int_from_bytes
from backend.srp import int_to_bytes
from backend.srp import int_to_padded_bytes
from backend.srp import mgf1_sha1
from backend.srp import sha1
from backend.srp import xor_bytes
from backend import disk_rpc
from backend import firmware_session
from backend import legacy_cli
from backend import session as acp_session
from backend import wireless_clients

# ---------------------------------------------------------------------------
# Modern write/RPC helpers
# ---------------------------------------------------------------------------

SET_PROPERTY_COMMAND = 0x15
LEGACY_FIRMWARE_COMMAND = 0x03
PARSE_DIRTY_PLIST = "acpd.parseDirtyPlist"
SET_DIRTY_PLIST = "acpd.setDirtyPlist"
SYSTEM_INTERFACES = "acpd.system.interfaces"
ERASE_DISK = "diskd.eraseDisk"
ARCHIVE_DISK = "diskd.archiveDisk"
from backend.intents import json_safe_rpc_value
from backend.intents import modern_dirty_plist_value_bytes
from backend.intents import normalized_action_intent
from backend.intents import normalized_dirty_properties
from backend.intents import normalized_firmware_upload_intent
from backend.intents import normalized_intent_value
from backend.intents import normalized_legacy_write_intent
from backend.intents import normalized_modern_write_intent
from backend.intents import value_from_json_setting
from backend.settings import CONNECT_USING_VALUES
from backend.settings import DHCP_LEASE_UNITS
from backend.settings import DISK_SECURITY_VALUES
from backend.settings import GUEST_DISK_ACCESS_VALUES
from backend.settings import has_friendly_setting_options
from backend.settings import IPV6_CONFIG_VALUES
from backend.settings import IPV6_MODE_VALUES
from backend.settings import LEGACY_ROUTER_MODE_VALUES
from backend.settings import PPPOE_CONNECTION_VALUES
from backend.settings import PROFILE_RADIO_DIRTY_KEYS
from backend.settings import PROFILE_TOP_LEVEL_DIRTY_KEYS
from backend.settings import RADIO_MODE_VALUES
from backend.settings import ROUTER_MODE_VALUES
from backend.settings import WDS_MODE_VALUES
from backend.settings import WIRELESS_MODE_VALUES
from backend.settings import WIRELESS_SECURITY_VALUES
from backend.settings import add_advanced_arguments
from backend.settings import add_network_arguments
from backend.settings import build_network_dirty_plist
from backend.settings import raw_text_setting_value
from backend.settings import required_text
from backend.settings import validate_setting_name
from backend.settings import wpa_preshared_key
from backend.settings import wds_node_list_value
from backend.cfb0 import CFB0CodecError
from backend.cfb0 import CFB0CodecError as CFB0Error
from backend.cfb0 import CFB0_MAGIC
from backend.cfb0 import CFB0Reader
from backend.cfb0 import cfb0_dumps
from backend.cfb0 import cfb0_int
from backend.cfb0 import cfb0_loads
from backend.cfb0 import cfb0_value
from backend.disk import DEFAULT_ARCHIVE_MESSAGE
from backend.disk import DEFAULT_ARCHIVE_NAME
from backend.disk import DEFAULT_ERASE_MESSAGE
from backend.disk import DEFAULT_ERASE_VOLUME_NAME
from backend.disk import ERASE_METHOD_VALUES
from backend.disk import default_archive_name
from backend.disk import disk_is_builtin
from backend.disk import iter_mast_disks
from backend.disk import iter_mast_partitions
from backend.disk import matching_partitions
from backend.disk import parse_uuid_bytes
from backend.disk import partition_label
from backend.disk import partition_size_used
from backend.disk import partition_uuid
from backend.disk import partition_volume_name
from backend.disk import select_archive_partition
from backend.disk import select_mast_disk_without_partitions
from backend.disk import select_mast_partition
from backend.firmware import FIRMWARE_MAGIC
from backend.firmware import FIRMWARE_MAX_STREAM_SIZE
from backend.firmware import FIRMWARE_PROGRESS_OUTPUT_PREFIX
from backend.firmware import FIRMWARE_PROGRESS_POLL_SECONDS
from backend.firmware import FIRMWARE_PROGRESS_PROPERTY
from backend.firmware import FIRMWARE_PROGRESS_TIMEOUT_SECONDS
from backend.firmware import FIRMWARE_REBOOT_PROPERTY
from backend.firmware import FIRMWARE_REQUEST_FLAGS
from backend.firmware import FIRMWARE_START_PROPERTY
from backend.firmware import FIRMWARE_UPLOAD_CAPABILITY
from backend.firmware import FIRMWARE_UPLOAD_PROPERTY
from backend.firmware import firmware_link_local_address_from_mac
from backend.firmware import firmware_source_bytes
from backend.firmware import firmware_source_summary
from backend.firmware import firmware_upload_host_candidates
from backend.firmware import format_mac_address
from backend.firmware import is_ipv6_link_local_host
from backend.firmware import parse_firmware_image_info
from backend.firmware import parse_firmware_progress
from backend.firmware import parse_mac_address
from backend.firmware import resolved_ipv6_link_local_hosts
from backend.firmware import route_interface_for_host
from backend.modern import format_python_value
from backend.modern import format_value
from backend.modern import handle_property_result
from backend.modern import is_property_stream_terminator
from backend.modern import json_safe_cfb0
from backend.modern import modern_read_main
from backend.modern import next_unreturned_setting
from backend.modern import parse_property_record
from backend.modern import profile_path_get
from backend.modern import profile_path_parts
from backend.modern import property_error_description
from backend.modern import property_request
from backend.modern import read_profile_path
from backend.modern import read_properties
from backend.modern import read_property
from backend.modern import read_setting
from backend.modern import read_setting_bytes
from backend.modern import read_settings_bytes
from backend.modern import setting_json_record
from backend.legacy import ACPAuthError
from backend.legacy import ACPError
from backend.legacy import ACP_MAGIC as LEGACY_ACP_MAGIC
from backend.legacy import ACP_PORT as LEGACY_ACP_PORT
from backend.legacy import ACPPropertyError
from backend.legacy import ACPProtocolError
from backend.legacy import ACP_STATIC_KEY
from backend.legacy import ACP_VERSION
from backend.legacy import COMMAND_GETPROP
from backend.legacy import COMMAND_REBOOT
from backend.legacy import COMMAND_SETPROP
from backend.legacy import HEADER
from backend.legacy import LEGACY_IPV4_VALUE_SETTINGS
from backend.legacy import PRINTABLE
from backend.legacy import PROPERTY_HEADER
from backend.legacy import STREAMING_BODY_CHECKSUM
from backend.legacy import SUPPORTED_ACP_RESPONSE_VERSIONS
from backend.legacy import adler32_i32
from backend.legacy import bool_value
from backend.legacy import compose_header
from backend.legacy import compose_property_element
from backend.legacy import compose_streaming_header
from backend.legacy import decode_auto
from backend.legacy import encode_setting_value
from backend.legacy import format_error_code
from backend.legacy import generate_acp_header_key
from backend.legacy import generate_acp_keystream
from backend.legacy import get_property_raw
from backend.legacy import int16_value
from backend.legacy import int32_value
from backend.legacy import legacy_apply_dirty
from backend.legacy import legacy_format_value
from backend.legacy import legacy_parse_header
from backend.legacy import legacy_parse_property_header
from backend.legacy import legacy_read_settings_bytes
from backend.legacy import legacy_read_settings_bytes_acp17
from backend.legacy import legacy_setting_json_record
from backend.legacy import parse_property_results
from backend.legacy import read_property_result
from backend.legacy import recv_exact
from backend.legacy import send_property_write
from backend.legacy import send_property_write_streaming
from backend.legacy import send_property_write_streaming_acp17
from backend.legacy import send_reboot
from backend.legacy import signed_i32

def acp_header_token(text: str) -> bytes:
    return acp_session.acp_header_token(text)

def rpc_call(
    transport: ACPEncryptedTransport,
    function: str,
    inputs: dict[str, Any],
    flags: int,
) -> dict[str, Any]:
    return acp_session.rpc_call(transport, function, inputs, flags)

def open_encrypted_transport(host: str, password: str) -> tuple[Any, ACPEncryptedTransport]:
    return acp_session.open_encrypted_transport(
        host,
        password,
        connect=connect_acp,
        authenticate_func=authenticate,
        derive_keys_func=derive_keys,
    )

def read_back_with_retries(host: str, password: str, setting: str, attempts: int = 12) -> bytes:
    """Read a setting, retrying while the base station finishes a restart."""

    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            sock, transport = open_encrypted_transport(host, password)
            with sock:
                return read_property(transport, setting)
        except Exception as exc:
            last_error = exc
            if attempt + 1 < attempts:
                time.sleep(5)
    raise RuntimeError(f"could not read {setting} after write: {last_error}")

def read_cfb0_setting(host: str, password: str, setting: str) -> Any:
    sock, transport = open_encrypted_transport(host, password)
    with sock:
        value = read_property(transport, setting)
    if not value.startswith(b"CFB0"):
        raise ValueError(f"{setting} is not a CFB0 setting")
    return cfb0_loads(value)

def build_erase_disk_options(
    host: str,
    password: str,
    method_name: str,
    volume_name: str | None,
    uuid_text: str | None,
    message: str | None,
) -> tuple[dict[str, Any], str]:
    """Build AirPort Utility's disk erase option dictionary."""

    return disk_rpc.build_erase_disk_options(
        host,
        password,
        method_name,
        volume_name,
        uuid_text,
        message,
        read_cfb0_setting=read_cfb0_setting,
    )

def build_archive_disk_options(
    host: str,
    password: str,
    source_uuid_text: str | None,
    destination_uuid_text: str | None,
    source_name: str | None,
    destination_name: str | None,
    archive_name: str | None,
    message: str | None,
) -> tuple[dict[str, Any], str, str]:
    """Build AirPort Utility's disk archive option dictionary."""

    return disk_rpc.build_archive_disk_options(
        host,
        password,
        source_uuid_text,
        destination_uuid_text,
        source_name,
        destination_name,
        archive_name,
        message,
        read_cfb0_setting=read_cfb0_setting,
    )

def add_profile_backed_dirty_settings(
    host: str,
    password: str,
    dirty: dict[str, Any],
) -> None:
    """Mirror settings into Prof for base stations that ignore flat profile keys."""

    profile_keys = (PROFILE_TOP_LEVEL_DIRTY_KEYS | PROFILE_RADIO_DIRTY_KEYS) & set(dirty)
    if not profile_keys or "Prof" in dirty:
        return

    try:
        profile = read_cfb0_setting(host, password, "Prof")
    except Exception:
        return
    if not isinstance(profile, dict):
        return

    changed = False
    has_profile_bsrm = False
    has_profile_ratr = False
    profile_targets = []
    restore_profile = profile.get("restoreProfile")
    if isinstance(restore_profile, dict):
        profile_targets.append(restore_profile)
    profiles = profile.get("profiles")
    if isinstance(profiles, list):
        profile_targets.extend(item for item in profiles if isinstance(item, dict))

    for target in profile_targets:
        for key in PROFILE_TOP_LEVEL_DIRTY_KEYS & profile_keys:
            if key in target:
                target[key] = dirty[key]
                changed = True
                if key == "bsRM":
                    has_profile_bsrm = True
        if "bsRM" in profile_keys and "raTr" in target:
            router_mode_name = next(
                (name for name, value in ROUTER_MODE_VALUES.items() if value == dirty["bsRM"]),
                None,
            )
            if router_mode_name in LEGACY_ROUTER_MODE_VALUES:
                target["raTr"] = LEGACY_ROUTER_MODE_VALUES[router_mode_name]
                changed = True
                has_profile_ratr = True
        wifi = target.get("WiFi")
        radios = wifi.get("radios") if isinstance(wifi, dict) else None
        if not isinstance(radios, list):
            continue
        for radio in radios:
            if not isinstance(radio, dict):
                continue
            for key in PROFILE_RADIO_DIRTY_KEYS & profile_keys:
                if key in radio:
                    radio[key] = dirty[key]
                    changed = True

    if changed:
        dirty["Prof"] = profile
        if "bsRM" in dirty and has_profile_ratr and not has_profile_bsrm:
            del dirty["bsRM"]

def erase_disk(
    host: str,
    password: str,
    options: dict[str, Any],
    dry_run: bool = False,
) -> dict[str, Any]:
    """Run the destructive disk erase RPC or return an empty dry-run response."""

    if dry_run:
        return {}

    return disk_rpc.erase_disk(
        host,
        password,
        options,
        open_encrypted_transport=open_encrypted_transport,
        rpc_call=rpc_call,
    )

def archive_disk(
    host: str,
    password: str,
    options: dict[str, Any],
    dry_run: bool = False,
) -> dict[str, Any]:
    """Run the disk archive RPC or return an empty dry-run response."""

    if dry_run:
        return {}

    return disk_rpc.archive_disk(
        host,
        password,
        options,
        open_encrypted_transport=open_encrypted_transport,
        rpc_call=rpc_call,
    )

def read_u32_property(transport: ACPEncryptedTransport, setting: str) -> int:
    """Read a base station property as a big-endian unsigned integer."""

    return firmware_session.read_u32_property(transport, setting)

def supports_firmware_property_upload(transport: ACPEncryptedTransport) -> bool:
    """Return whether the base station advertises the modern firmware path."""

    return firmware_session.supports_firmware_property_upload(transport)

def host_supports_firmware_property_upload(host: str, password: str) -> bool:
    """Check firmware upload capability on its own ACP connection."""

    return firmware_session.host_supports_firmware_property_upload(
        host,
        password,
        open_encrypted_transport=open_encrypted_transport,
    )

def preflight_firmware_upload(
    host: str,
    password: str,
    firmware_info: dict[str, Any],
) -> dict[str, Any]:
    """Check the live device facts AirPort Utility checks before upload."""

    return firmware_session.preflight_firmware_upload(
        host,
        password,
        firmware_info,
        open_encrypted_transport=open_encrypted_transport,
    )

def send_property_stream(
    transport: ACPEncryptedTransport,
    setting: str,
    value: bytes,
    request_flags: int = FIRMWARE_REQUEST_FLAGS,
    progress_callback: Callable[[int, int], None] | None = None,
) -> None:
    """Write one ACP property through command 0x15 streaming mode."""

    validate_setting_name(setting)
    if len(value) > FIRMWARE_MAX_STREAM_SIZE:
        raise ValueError(f"property {setting} is too large: {len(value)} bytes")

    transport.send_stream_header(flags=request_flags, command=SET_PROPERTY_COMMAND)
    header, body = transport.recv()
    if header.status:
        raise RuntimeError(f"property stream setup failed with ACP status {header.status}")
    if body:
        raise RuntimeError("property stream setup returned an unexpected response body")

    transport.send_encrypted_stream(
        ACP_PROPERTY_HEADER.pack(setting.encode("ascii"), 0, len(value))
    )
    if value:
        if progress_callback is None:
            transport.send_encrypted_stream(value)
        else:
            transport.send_encrypted_stream(value, progress_callback=progress_callback)

    transport.send_encrypted_stream(
        ACP_PROPERTY_HEADER.pack(b"\x00\x00\x00\x00", 0, 4) + struct.pack(">I", 0)
    )
    first_error: tuple[str, int] | None = None
    while True:
        name, flags, size = parse_property_record(
            transport.recv_decrypted(ACP_PROPERTY_HEADER.size)
        )
        if size != 4:
            raise RuntimeError(
                f"property {setting} returned unexpected stream status size {size}"
            )
        status_data = transport.recv_decrypted(size)
        status = struct.unpack(">i", status_data)[0]
        if first_error is None and (flags & 1 or status):
            first_error = (name or setting, status)
        if name is None:
            break
    if first_error is not None:
        label, status = first_error
        raise RuntimeError(f"property {label} returned ACP status {status}")

def write_property_stream(
    host: str,
    password: str,
    setting: str,
    value: bytes,
    request_flags: int = FIRMWARE_REQUEST_FLAGS,
) -> None:
    """Write one property through an authenticated encrypted ACP stream."""

    sock, transport = open_encrypted_transport(host, password)
    with sock:
        send_property_stream(
            transport,
            setting,
            value,
            request_flags=request_flags,
        )

def modern_property_write_main(argv: list[str] | None = None) -> int:
    """Send a direct command-0x15 property write over modern encrypted ACP."""

    parser = argparse.ArgumentParser(
        description="Write one AirPort property through an encrypted ACP stream."
    )
    parser.add_argument("host", help="AirPort base station IP address or hostname")
    parser.add_argument("--password", required=True, help="admin password")
    parser.add_argument("--setting", required=True, help="four-character ACP setting name")
    value_group = parser.add_mutually_exclusive_group(required=True)
    value_group.add_argument("--value", help="raw UTF-8 property value")
    value_group.add_argument("--value-json", help="typed JSON property value")
    parser.add_argument(
        "--request-flags",
        type=lambda value: int(value, 0),
        default=FIRMWARE_REQUEST_FLAGS,
        help="ACP request flags for the property stream; default: 4",
    )
    args = parser.parse_args(argv)

    try:
        validate_setting_name(args.setting)
        if not 0 <= args.request_flags <= 0xFFFFFFFF:
            raise ValueError("--request-flags must fit in an unsigned 32-bit integer")

        if args.value_json is not None:
            try:
                value = value_from_json_setting(json.loads(args.value_json))
            except json.JSONDecodeError as exc:
                raise ValueError(f"--value-json is not valid JSON: {exc}") from None
            if not isinstance(value, bytes):
                raise ValueError(
                    "--value-json must decode to bytes for a direct property-stream write"
                )
        else:
            value = args.value.encode("utf-8")

        write_property_stream(
            args.host,
            args.password,
            args.setting,
            value,
            request_flags=args.request_flags,
        )
        print(f"encrypted ACP property stream accepted: {args.setting}.")
        return 0
    except (OSError, RuntimeError, ValueError, TypeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

def prepare_firmware_upload_session(transport: ACPEncryptedTransport) -> dict[str, Any]:
    """Run AirPort Utility's same-session firmware pre-upload probes."""

    result: dict[str, Any] = {}
    for setting in ("raSL", "sySt"):
        try:
            value = read_property(transport, setting, flags=FIRMWARE_REQUEST_FLAGS)
            result[setting] = {"available": True, "length": len(value)}
        except Exception as exc:
            result[setting] = {"available": False, "error": str(exc)}
        if setting == "raSL":
            try:
                response = rpc_call(
                    transport,
                    SYSTEM_INTERFACES,
                    {},
                    flags=FIRMWARE_REQUEST_FLAGS,
                )
                outputs = response.get("outputs", {})
                result[SYSTEM_INTERFACES] = {
                    "available": True,
                    "keys": sorted(outputs.keys()) if isinstance(outputs, dict) else [],
                }
            except Exception as exc:
                result[SYSTEM_INTERFACES] = {"available": False, "error": str(exc)}
    return result


def read_modern_wireless_clients(
    host: str,
    password: str,
    *,
    discover_identities: bool = False,
    diagnostic: Callable[[str], None] | None = None,
) -> list[dict[str, Any]]:
    """Read AirPort Utility's radio/interface client sources in one session."""

    sock, transport = open_encrypted_transport(host, password)
    radio_station_list: Any = {}
    interfaces: Any = {}
    errors: list[str] = []
    with sock:
        try:
            radio_station_list = cfb0_loads(
                read_property(transport, "raSL", flags=FIRMWARE_REQUEST_FLAGS)
            )
        except Exception as exc:
            errors.append(f"raSL: {exc}")
        try:
            interfaces = rpc_call(
                transport,
                SYSTEM_INTERFACES,
                {},
                flags=FIRMWARE_REQUEST_FLAGS,
            )
        except Exception as exc:
            errors.append(f"{SYSTEM_INTERFACES}: {exc}")
    if len(errors) == 2:
        raise RuntimeError("; ".join(errors))
    macs, details_by_mac = wireless_clients.modern_wireless_client_details(
        radio_station_list, interfaces
    )
    neighbor_addresses = (
        wireless_clients.discover_neighbor_cache(host, diagnostic=diagnostic)
        if discover_identities
        else wireless_clients.read_neighbor_cache()
    )
    return wireless_clients.resolved_client_records(
        macs,
        neighbor_addresses=neighbor_addresses,
        details_by_mac=details_by_mac,
        hostname_lookup_budget_seconds=3.0 if discover_identities else 1.0,
        diagnostic=diagnostic,
    )


def read_legacy_wireless_clients(
    host: str,
    community: str,
    *,
    discover_identities: bool = False,
    diagnostic: Callable[[str], None] | None = None,
) -> list[dict[str, Any]]:
    """Read associated legacy stations and correlate their DHCP addresses."""

    walk = wireless_clients.run_legacy_snmp_walk(host, community)
    macs, dhcp_addresses, details_by_mac = (
        wireless_clients.parse_legacy_snmp_client_details(walk)
    )
    neighbor_addresses = (
        wireless_clients.discover_neighbor_cache(host, diagnostic=diagnostic)
        if discover_identities
        else wireless_clients.read_neighbor_cache()
    )
    return wireless_clients.resolved_client_records(
        macs,
        addresses_by_mac=dhcp_addresses,
        neighbor_addresses=neighbor_addresses,
        details_by_mac=details_by_mac,
        hostname_lookup_budget_seconds=3.0 if discover_identities else 1.0,
        diagnostic=diagnostic,
    )


def wireless_clients_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="List currently associated wireless AirPort clients."
    )
    parser.add_argument("host", help="AirPort base station IP address or hostname")
    parser.add_argument("--password", help="admin password for modern ACP")
    parser.add_argument(
        "--legacy",
        action="store_true",
        help="use the legacy AirPort SNMP client table",
    )
    parser.add_argument("--snmp-community", help="legacy AirPort SNMP community")
    parser.add_argument(
        "--discover-identities",
        action="store_true",
        help="discover local IP and cross-platform host identities",
    )
    parser.add_argument("--json", action="store_true", help="print structured JSON")
    args = parser.parse_args(argv)

    def identity_diagnostic(message: str) -> None:
        print(f"identity discovery: {message}", file=sys.stderr, flush=True)

    identity_diagnostic(
        f"enabled={str(args.discover_identities).lower()}; host={args.host}"
    )
    diagnostic = identity_diagnostic if args.discover_identities else None

    try:
        if args.legacy:
            if not args.snmp_community:
                raise ValueError("--snmp-community is required with --legacy")
            clients = read_legacy_wireless_clients(
                args.host,
                args.snmp_community,
                discover_identities=args.discover_identities,
                diagnostic=diagnostic,
            )
        else:
            if args.password is None:
                raise ValueError("--password is required for modern ACP")
            clients = read_modern_wireless_clients(
                args.host,
                args.password,
                discover_identities=args.discover_identities,
                diagnostic=diagnostic,
            )
        result: dict[str, Any] = {"clients": clients}
        if args.discover_identities:
            note = wireless_clients.local_network_mismatch_note(args.host)
            if note is not None:
                result["clientDiscoveryNote"] = note
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            for client in clients:
                print(client["hostname"] or client["ipAddress"])
        return 0
    except (
        ACPError,
        CFB0CodecError,
        OSError,
        RuntimeError,
        ValueError,
        TypeError,
    ) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

def wait_for_firmware_progress(
    transport: ACPEncryptedTransport,
    timeout_seconds: float = FIRMWARE_PROGRESS_TIMEOUT_SECONDS,
    poll_seconds: float = FIRMWARE_PROGRESS_POLL_SECONDS,
    progress_callback: Callable[[dict[str, Any]], None] | None = None,
) -> dict[str, Any]:
    """Poll `fugp` after `fust`, keeping the ACP session open like AirPort Utility."""

    deadline = time.monotonic() + timeout_seconds
    last_progress: dict[str, Any] | None = None
    while time.monotonic() < deadline:
        try:
            progress = parse_firmware_progress(
                read_property(
                    transport,
                    FIRMWARE_PROGRESS_PROPERTY,
                    flags=FIRMWARE_REQUEST_FLAGS,
                )
            )
        except Exception as exc:
            if last_progress is None:
                return {
                    "available": False,
                    "complete": False,
                    "error": str(exc),
                }
            last_progress["available"] = True
            last_progress["interrupted"] = True
            last_progress["error"] = str(exc)
            return last_progress

        progress["available"] = True
        last_progress = progress
        if progress_callback is not None:
            progress_callback(progress)
        if progress["complete"]:
            return progress
        time.sleep(poll_seconds)

    if last_progress is None:
        return {
            "available": False,
            "complete": False,
            "error": "firmware progress did not become available before timeout",
        }
    raise RuntimeError(
        "firmware upload progress did not complete before timeout: "
        f"{last_progress['current']}/{last_progress['total']}"
    )

def emit_firmware_upload_progress(
    phase: str,
    current: int,
    total: int,
    raw: str | None = None,
) -> None:
    """Print one machine-readable firmware progress event for the GUI."""

    event: dict[str, Any] = {
        "phase": phase,
        "current": current,
        "total": total,
        "complete": total > 0 and current >= total,
    }
    if raw:
        event["raw"] = raw
    print(
        FIRMWARE_PROGRESS_OUTPUT_PREFIX + json.dumps(event, sort_keys=True),
        flush=True,
    )

def call_send_property_stream(
    transport: ACPEncryptedTransport,
    setting: str,
    value: bytes,
    request_flags: int = FIRMWARE_REQUEST_FLAGS,
    progress_callback: Callable[[int, int], None] | None = None,
) -> None:
    """Call the property-stream helper while preserving old monkeypatch signatures."""

    parameters = inspect.signature(send_property_stream).parameters
    if progress_callback is not None and "progress_callback" in parameters:
        send_property_stream(
            transport,
            setting,
            value,
            request_flags=request_flags,
            progress_callback=progress_callback,
        )
    else:
        send_property_stream(
            transport,
            setting,
            value,
            request_flags=request_flags,
        )

def call_wait_for_firmware_progress(
    transport: ACPEncryptedTransport,
    progress_callback: Callable[[dict[str, Any]], None] | None = None,
) -> dict[str, Any]:
    """Call the progress poller while preserving old monkeypatch signatures."""

    if progress_callback is not None and "progress_callback" in inspect.signature(
        wait_for_firmware_progress
    ).parameters:
        return wait_for_firmware_progress(
            transport,
            progress_callback=progress_callback,
        )
    return wait_for_firmware_progress(transport)

def upload_firmware_with_properties(
    transport: ACPEncryptedTransport,
    firmware_data: bytes,
    progress_callback: Callable[[str, int, int, str | None], None] | None = None,
) -> dict[str, Any]:
    """Upload firmware using AirPort Utility's newer `fuup`/`fust` path."""

    session_preparation = prepare_firmware_upload_session(transport)
    def upload_progress(sent: int, total: int) -> None:
        if progress_callback is not None:
            progress_callback("upload", sent, total, None)

    def program_progress(progress: dict[str, Any]) -> None:
        if progress_callback is not None:
            progress_callback(
                "program",
                int(progress.get("current") or 0),
                int(progress.get("total") or 0),
                str(progress.get("raw") or ""),
            )

    call_send_property_stream(
        transport,
        FIRMWARE_UPLOAD_PROPERTY,
        firmware_data,
        progress_callback=upload_progress if progress_callback is not None else None,
    )
    call_send_property_stream(transport, FIRMWARE_START_PROPERTY, b"")
    progress = call_wait_for_firmware_progress(
        transport,
        progress_callback=program_progress if progress_callback is not None else None,
    )
    reboot_command = {"sent": False}
    if progress.get("complete"):
        call_send_property_stream(
            transport,
            FIRMWARE_REBOOT_PROPERTY,
            b"",
            request_flags=0,
        )
        reboot_command = {"sent": True, "property": FIRMWARE_REBOOT_PROPERTY}
    return {
        "method": "property-stream",
        "size": len(firmware_data),
        "progress": progress,
        "sessionPreparation": session_preparation,
        "rebootCommand": reboot_command,
    }

def upload_firmware_legacy(
    transport: ACPEncryptedTransport,
    firmware_data: bytes,
    progress_callback: Callable[[str, int, int, str | None], None] | None = None,
) -> dict[str, Any]:
    """Upload firmware using AirPort Utility's direct command 0x03 path."""

    if progress_callback is not None:
        progress_callback("upload", 0, len(firmware_data), None)
    transport.send(firmware_data, flags=0, command=LEGACY_FIRMWARE_COMMAND)
    if progress_callback is not None:
        progress_callback("upload", len(firmware_data), len(firmware_data), None)
    return {"method": "legacy-command", "size": len(firmware_data)}

def call_firmware_upload_function(
    upload_function: Callable[..., dict[str, Any]],
    transport: ACPEncryptedTransport,
    firmware_data: bytes,
    progress_callback: Callable[[str, int, int, str | None], None] | None,
) -> dict[str, Any]:
    """Call upload helpers while preserving tests that monkeypatch old signatures."""

    if "progress_callback" in inspect.signature(upload_function).parameters:
        return upload_function(
            transport,
            firmware_data,
            progress_callback=progress_callback,
        )
    return upload_function(transport, firmware_data)

def upload_firmware(
    host: str,
    password: str,
    source: str,
    dry_run: bool = False,
) -> dict[str, Any]:
    """Upload firmware using the transfer paths found in AirPort Utility."""

    firmware_source_summary(source)
    if dry_run:
        return {}

    if "://" in source.strip():
        firmware_source_bytes(source)

    firmware_data = firmware_source_bytes(source, max_size=FIRMWARE_MAX_STREAM_SIZE)
    firmware_info = parse_firmware_image_info(firmware_data)
    preflight = preflight_firmware_upload(host, password, firmware_info)
    has_property_upload = bool(preflight["supportsPropertyUpload"])
    upload_hosts = (
        firmware_upload_host_candidates(host, preflight)
        if has_property_upload
        else [host]
    )

    open_errors: list[str] = []
    result: dict[str, Any] | None = None
    upload_host = host
    for candidate_host in upload_hosts:
        try:
            sock, transport = open_encrypted_transport(candidate_host, password)
        except Exception as exc:
            open_errors.append(f"{candidate_host}: {exc}")
            continue
        upload_host = candidate_host
        with sock:
            sock.settimeout(60)
            if has_property_upload:
                result = call_firmware_upload_function(
                    upload_firmware_with_properties,
                    transport,
                    firmware_data,
                    emit_firmware_upload_progress,
                )
            else:
                result = call_firmware_upload_function(
                    upload_firmware_legacy,
                    transport,
                    firmware_data,
                    emit_firmware_upload_progress,
                )
        break

    if result is None:
        details = "; ".join(open_errors) if open_errors else "no upload hosts were available"
        raise OSError(f"could not open firmware upload connection: {details}")
    result["firmware"] = firmware_info
    result["preflight"] = preflight
    result["requestedHost"] = host
    result["uploadHost"] = upload_host
    result["uploadHostCandidates"] = upload_hosts
    return result

def write_dirty_settings(
    host: str,
    password: str,
    dirty_plist: dict[str, Any],
    readback_setting: str | None = None,
    verify_setting: str | None = None,
    verify_password: str | None = None,
    dry_run: bool = False,
) -> tuple[dict[str, Any], bytes | None]:
    """Write dirty settings and return the set RPC response plus optional readback bytes."""

    if not dirty_plist:
        raise ValueError("no settings were provided")
    for setting in dirty_plist:
        validate_setting_name(setting)
    if readback_setting is not None:
        validate_setting_name(readback_setting)
    if verify_setting is not None:
        validate_setting_name(verify_setting)

    sock, transport = open_encrypted_transport(host, password)
    readback = None
    with sock:
        parse_response = rpc_call(
            transport,
            PARSE_DIRTY_PLIST,
            {
                "drTY": dirty_plist,
                "allowMinimal": True,
            },
            flags=4,
        )
        if dry_run:
            return parse_response, None
        set_response = rpc_call(
            transport,
            SET_DIRTY_PLIST,
            {
                "drTY": dirty_plist,
                "allowMinimal": True,
            },
            flags=0,
        )
        if readback_setting is not None:
            try:
                readback = read_property(transport, readback_setting)
            except Exception:
                readback = read_back_with_retries(
                    host,
                    verify_password or password,
                    readback_setting,
                )

    if verify_setting is not None:
        read_back_with_retries(host, verify_password or password, verify_setting)

    return set_response, readback

def write_text_setting(
    host: str,
    password: str,
    setting: str,
    value: str,
) -> tuple[dict[str, Any], bytes | None]:
    """Write one text setting and return the set RPC response plus optional readback bytes."""

    if setting == "syPW":
        # The admin password is write-only. Verify the change by opening a
        # fresh session with the new password and reading a harmless field.
        return write_dirty_settings(
            host,
            password,
            {setting: value},
            verify_setting="syNm",
            verify_password=value,
            dry_run=False,
        )

    return write_dirty_settings(host, password, {setting: value}, readback_setting=setting)

def modern_write_main(argv: list[str] | None = None) -> int:
    """Command-line entry point."""

    parser = argparse.ArgumentParser(description="Write AirPort/Time Capsule settings.")
    parser.add_argument("host", help="Time Capsule IP address or hostname")
    parser.add_argument("--password", required=True, help="admin password")
    parser.add_argument("--setting", default="syNm", help="four-character ACP setting name, e.g. syNm")
    parser.add_argument("--value", help="new text value for --setting")
    parser.add_argument("--value-json", help="new JSON value for --setting, for structured settings")
    parser.add_argument(
        "--values-json",
        help="ordered JSON object of four-character ACP setting names to values",
    )
    parser.add_argument("--dry-run", action="store_true", help="validate dirty plist without committing it")
    parser.add_argument(
        "--no-verify",
        action="store_true",
        help="return after a successful write without opening a readback session",
    )
    parser.add_argument(
        "--dry-run-json",
        action="store_true",
        help="print normalized protocol intent without contacting the base station",
    )
    parser.add_argument(
        "--setup-complete",
        action="store_true",
        help="write the setup-completion timestamp (ctim)",
    )
    parser.add_argument(
        "--setup-complete-timestamp",
        type=int,
        help="Core Foundation timestamp to use with --setup-complete; defaults to now",
    )
    add_network_arguments(parser)
    args = parser.parse_args(argv)

    try:
        dirty_plist: dict[str, Any] = {}
        readback_setting = None
        verify_setting = None
        verify_password = None

        if sum(value is not None for value in (args.value, args.value_json, args.values_json)) > 1:
            raise ValueError("use only one of --value, --value-json, or --values-json")

        actions = [
            args.erase_disk,
            args.archive_disk,
            args.upload_firmware is not None,
        ]
        if sum(1 for action in actions if action) > 1:
            raise ValueError("use only one of --erase-disk, --archive-disk, or --upload-firmware")

        has_setting_changes = (
            args.value is not None
            or args.value_json is not None
            or args.values_json is not None
            or has_friendly_setting_options(args)
        )

        if args.erase_disk:
            if has_setting_changes:
                raise ValueError("do not combine --erase-disk with setting changes")
            if args.dry_run_json:
                options = {
                    key: value
                    for key, value in {
                        "method": ERASE_METHOD_VALUES[args.erase_method],
                        "volumeName": args.volume_name,
                        "message": args.erase_message or DEFAULT_ERASE_MESSAGE,
                        "uuid": parse_uuid_bytes(args.partition_uuid) if args.partition_uuid else None,
                    }.items()
                    if value is not None
                }
                print(json.dumps(normalized_action_intent(args.host, ERASE_DISK, options), indent=2, sort_keys=True))
                return 0
            if not args.dry_run and not args.i_know_this_erases_the_disk:
                raise ValueError("--erase-disk requires --i-know-this-erases-the-disk without --dry-run")
            options, selected = build_erase_disk_options(
                args.host,
                args.password,
                args.erase_method,
                args.volume_name,
                args.partition_uuid,
                args.erase_message,
            )
            print("erase-disk options:")
            print(json.dumps(json_safe_rpc_value(options), indent=2, sort_keys=True))
            if args.dry_run:
                print(f"dry-run accepted: {ERASE_DISK} for {selected}")
                return 0
            response = erase_disk(args.host, args.password, options)
            result = response.get("outputs", {}).get("result") if isinstance(response.get("outputs"), dict) else None
            if result is not None:
                print(f"result: {result}")
            print(f"erase started: {selected}")
            return 0

        if args.archive_disk:
            if has_setting_changes:
                raise ValueError("do not combine --archive-disk with setting changes")
            if args.dry_run_json:
                options = {
                    key: value
                    for key, value in {
                        "archiveName": args.archive_name,
                        "sourceUUID": args.archive_source_uuid,
                        "destinationUUID": args.archive_destination_uuid,
                        "sourceName": args.archive_source_name,
                        "destinationName": args.archive_destination_name,
                        "message": args.archive_message,
                    }.items()
                    if value is not None
                }
                print(json.dumps(normalized_action_intent(args.host, ARCHIVE_DISK, options), indent=2, sort_keys=True))
                return 0
            if not args.dry_run and not args.i_know_this_starts_the_archive:
                raise ValueError("--archive-disk requires --i-know-this-starts-the-archive without --dry-run")
            options, source, destination = build_archive_disk_options(
                args.host,
                args.password,
                args.archive_source_uuid,
                args.archive_destination_uuid,
                args.archive_source_name,
                args.archive_destination_name,
                args.archive_name,
                args.archive_message,
            )
            print("archive-disk options:")
            print(json.dumps(json_safe_rpc_value(options), indent=2, sort_keys=True))
            if args.dry_run:
                print(f"dry-run accepted: {ARCHIVE_DISK} from {source} to {destination}")
                return 0
            response = archive_disk(args.host, args.password, options)
            result = response.get("outputs", {}).get("result") if isinstance(response.get("outputs"), dict) else None
            if result is not None:
                print(f"result: {result}")
            print(f"archive started: {source} -> {destination}")
            return 0

        if args.upload_firmware is not None:
            if has_setting_changes:
                raise ValueError("do not combine --upload-firmware with setting changes")
            if args.dry_run_json:
                print(
                    json.dumps(
                        normalized_firmware_upload_intent(args.host, args.upload_firmware),
                        indent=2,
                        sort_keys=True,
                    )
                )
                return 0
            if not args.dry_run and not args.i_know_this_updates_firmware:
                raise ValueError(
                    "--upload-firmware requires --i-know-this-updates-firmware without --dry-run"
                )
            summary = firmware_source_summary(args.upload_firmware)
            print("firmware-upload options:")
            print(json.dumps({"source": args.upload_firmware}, indent=2, sort_keys=True))
            if args.dry_run:
                print(f"dry-run accepted: {summary}")
                return 0
            result = upload_firmware(args.host, args.password, args.upload_firmware, dry_run=False)
            print("firmware-upload result:")
            print(json.dumps(result, indent=2, sort_keys=True))
            print(f"firmware upload started: {summary}")
            return 0

        network_dirty_plist = build_network_dirty_plist(args)

        if args.values_json is not None:
            try:
                values_object = json.loads(args.values_json, object_pairs_hook=dict)
            except json.JSONDecodeError as exc:
                raise ValueError(f"--values-json is not valid JSON: {exc}") from None
            if not isinstance(values_object, dict) or not values_object:
                raise ValueError("--values-json must be a non-empty object")
            for setting, value in values_object.items():
                validate_setting_name(setting)
                dirty_plist[setting] = value_from_json_setting(value)
            if "syPW" in dirty_plist:
                verify_setting = "syNm"
                verify_password = dirty_plist["syPW"]
        elif args.value is not None:
            dirty_plist[args.setting] = raw_text_setting_value(args.setting, args.value)
            if args.setting == "syPW":
                verify_setting = "syNm"
                verify_password = dirty_plist[args.setting]
            else:
                readback_setting = args.setting
        elif args.value_json is not None:
            try:
                json_value = json.loads(args.value_json)
            except json.JSONDecodeError as exc:
                raise ValueError(f"--value-json is not valid JSON: {exc}") from None
            json_value = value_from_json_setting(json_value)
            if args.setting in {"syNm", "syPW"}:
                if not isinstance(json_value, str):
                    label = "Admin Password" if args.setting == "syPW" else "Base Station Name"
                    raise ValueError(f"{label} must be a text value")
                json_value = raw_text_setting_value(args.setting, json_value)
                if args.setting == "syPW":
                    verify_setting = "syNm"
                    verify_password = json_value
            dirty_plist[args.setting] = json_value
            if args.setting != "syPW":
                readback_setting = args.setting

        if network_dirty_plist:
            if (
                (args.value is not None or args.value_json is not None)
                and args.setting == "syPW"
                and set(network_dirty_plist) != {"ctim"}
            ):
                raise ValueError("do not combine a password change with network setting changes")
            collisions = sorted(set(dirty_plist) & set(network_dirty_plist))
            if collisions:
                raise ValueError(f"setting specified twice: {', '.join(collisions)}")
            dirty_plist.update(network_dirty_plist)
            readback_setting = None

        if not args.dry_run_json:
            add_profile_backed_dirty_settings(args.host, args.password, dirty_plist)

        if not dirty_plist:
            parser.error("provide --value or at least one network setting option")

        if args.dry_run_json:
            print(
                json.dumps(
                    normalized_modern_write_intent(args.host, dirty_plist),
                    indent=2,
                    sort_keys=True,
                )
            )
            return 0

        if args.no_verify:
            verify_setting = None
            readback_setting = None
        response, readback = write_dirty_settings(
            args.host,
            args.password,
            dirty_plist,
            readback_setting=readback_setting,
            verify_setting=None if args.dry_run else verify_setting,
            verify_password=verify_password,
            dry_run=args.dry_run,
        )
        result = response.get("outputs", {}).get("result") if isinstance(response.get("outputs"), dict) else None
        if result is not None:
            print(f"result: {result}")
        if args.dry_run:
            print(f"dry-run accepted: {', '.join(sorted(dirty_plist))}")
        elif readback is not None and readback_setting is not None:
            print(f"{readback_setting}: {format_value(readback)}")
        elif network_dirty_plist:
            print(f"changed: {', '.join(sorted(dirty_plist))}")
        else:
            print(f"{args.setting}: changed")
        return 0
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

def legacy_read_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read a legacy AirPort ACP setting.")
    parser.add_argument("host", help="AirPort base station IP address or hostname")
    parser.add_argument("--password", required=True, help="admin password")
    parser.add_argument(
        "--setting",
        action="append",
        help="four-character ACP setting name, e.g. sySN; repeat to batch-read settings",
    )
    parser.add_argument("--json", action="store_true", help="print structured output as JSON")
    parser.add_argument("--timeout", type=float, default=25.0, help="ACP connection timeout")
    parser.add_argument(
        "--acp17",
        action="store_true",
        help="negotiate the encrypted legacy transport used by product 3",
    )
    args = parser.parse_args(argv)

    if not args.setting:
        parser.error("--setting is required")
    for setting in args.setting:
        if len(setting.encode("ascii", errors="ignore")) != 4 or len(setting) != 4:
            parser.error(f"setting names must be exactly 4 ASCII characters: {setting!r}")
    if len(args.setting) > 1 and not args.json:
        parser.error("--json is required when reading multiple settings")

    try:
        if args.acp17:
            values, errors = legacy_read_settings_bytes_acp17(
                args.host, args.password, args.setting, args.timeout
            )
        else:
            values, errors = legacy_read_settings_bytes(
                args.host, args.password, args.setting, args.timeout
            )
        if args.json:
            print(
                json.dumps(
                    {
                        "settings": {
                            setting: legacy_setting_json_record(value)
                            for setting, value in values.items()
                        },
                        "errors": errors,
                    },
                    indent=2,
                    sort_keys=True,
                )
            )
        else:
            setting = args.setting[0]
            if setting in values:
                print(format_value(values[setting]))
            elif setting in errors:
                raise RuntimeError(errors[setting])
            else:
                raise RuntimeError(f"setting {setting!r} was not present in the response")
    except (ACPError, OSError, RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0

# ---------------------------------------------------------------------------
# Legacy write command
# ---------------------------------------------------------------------------

LEGACY_WRITE_NETWORK_DEFAULTS: dict[str, Any] = {
    "connect_using": None,
    "ipv4_address": None,
    "lan_ip_address": None,
    "subnet_mask": None,
    "router_address": None,
    "dns_server": None,
    "dns_server_1": None,
    "dns_server_2": None,
    "dns_server_3": None,
    "clear_dns": False,
    "ipv6_dns_server": None,
    "clear_ipv6_dns": False,
    "domain_name": None,
    "dhcp_client_id": None,
    "ipv6_address": None,
    "pppoe_account": None,
    "pppoe_password": None,
    "pppoe_service": None,
    "pppoe_connection": None,
    "pppoe_idle_seconds": None,
    "configure_ipv6": None,
    "ipv6_mode": None,
    "ipv6_default_route": None,
    "ipv6_firewall": None,
    "remote_ipv4_address": None,
    "ipv6_lan_address": None,
    "ipv6_lan_prefix_length": None,
    "ipv6_delegated_prefix": None,
    "ipv6_delegated_prefix_length": None,
    "ipv6_wan_prefix_length": None,
    "ipv6_connection_sharing": None,
    "dynamic_global_hostname": None,
    "global_hostname": None,
    "global_hostname_user": None,
    "global_hostname_password": None,
    "dynamic_global_hostname_auto_config": None,
    "allow_setup_over_wan": None,
    "router_mode": None,
    "dhcp_range_start": None,
    "dhcp_range_end": None,
    "dhcp_lease": None,
    "dhcp_lease_unit": "seconds",
    "nat_pmp": None,
    "default_host": None,
    "clear_default_host": False,
    "file_sharing": None,
    "share_disks_over_wan": None,
    "disk_security": None,
    "disk_password": None,
    "guest_disk_access": None,
    "share_disks_global_hostname": None,
    "wins_server": None,
    "windows_workgroup": None,
    "usb_file_sharing_flags": None,
    "disk_account_json": None,
}

def ensure_legacy_network_defaults(args: argparse.Namespace) -> None:
    legacy_cli.ensure_legacy_network_defaults(args, LEGACY_WRITE_NETWORK_DEFAULTS)

def build_dirty(args: argparse.Namespace) -> dict[str, Any]:
    return legacy_cli.build_dirty(args, LEGACY_WRITE_NETWORK_DEFAULTS)

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Write legacy AirPort ACP settings.")
    parser.add_argument("host", help="AirPort base station IP address or hostname")
    parser.add_argument("--password", required=True, help="admin password")
    parser.add_argument("--timeout", type=float, default=25.0, help="ACP connection timeout")
    parser.add_argument("--dry-run", action="store_true", help="validate and print changed keys")
    parser.add_argument(
        "--dry-run-json",
        action="store_true",
        help="print normalized protocol intent without contacting the base station",
    )
    parser.add_argument(
        "--restart",
        action="store_true",
        help="send legacy apply/restart markers in the streaming set-property transaction",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="send apply/restart markers in the streaming set-property transaction",
    )
    parser.add_argument(
        "--streaming",
        action="store_true",
        help="send the property write using ACP streaming framing",
    )
    parser.add_argument(
        "--acp17",
        action="store_true",
        help="negotiate the encrypted legacy transport used by product 3",
    )
    parser.add_argument(
        "--request-flags",
        type=lambda value: int(value, 0),
        default=4,
        help="ACP request flags for a streaming property write; default: 4",
    )
    parser.add_argument(
        "--no-apply",
        action="store_true",
        help="stage properties without sending the legacy apply/restart markers",
    )
    parser.add_argument(
        "--setup-complete",
        action="store_true",
        help="write the legacy setup-completion timestamp (ctim)",
    )
    parser.add_argument(
        "--setup-complete-timestamp",
        type=int,
        help="Core Foundation timestamp to use with --setup-complete; defaults to now",
    )
    parser.add_argument("--json", action="store_true", help="print structured output as JSON")
    parser.add_argument("--setting", help="raw four-character ACP setting name")
    parser.add_argument("--value", help="raw string value for --setting")
    parser.add_argument("--value-json", help="raw JSON value for --setting")
    parser.add_argument(
        "--values-json",
        help="ordered JSON object of raw ACP setting names and values",
    )
    parser.add_argument(
        "--base-values-json",
        help="ordered legacy snapshot to merge before explicit settings",
    )

    internet = parser.add_argument_group("Internet pane network settings")
    internet.add_argument(
        "--connect-using",
        choices=sorted(CONNECT_USING_VALUES),
        help="set Connect Using (waCV): dhcp, static, pppoe, or modem",
    )
    internet.add_argument("--ipv4-address", help="set IPv4 Address (waIP)")
    internet.add_argument("--lan-ip-address", help="set LAN IP Address (laIP)")
    internet.add_argument("--subnet-mask", help="set Subnet Mask (waSM)")
    internet.add_argument("--router-address", help="set Router Address (waRA)")
    internet.add_argument(
        "--dns-server",
        action="append",
        help="replace IPv4 DNS Servers (waD1/waD2); repeat or comma-separate",
    )
    internet.add_argument("--dns-server-1", help="set first IPv4 DNS Server slot only (waD1)")
    internet.add_argument("--dns-server-2", help="set second IPv4 DNS Server slot only (waD2)")
    internet.add_argument("--dns-server-3", help="set third IPv4 DNS Server slot only (waD3)")
    internet.add_argument("--clear-dns", action="store_true", help="clear IPv4 DNS Servers")
    internet.add_argument("--domain-name", help="set Domain Name (waDN)")
    internet.add_argument("--dhcp-client-id", help="set DHCP Client ID (waDC)")
    internet.add_argument("--modem-phone-number", help="set modem primary phone number (moPN)")
    internet.add_argument("--modem-alternate-number", help="set modem alternate phone number (moAP)")
    internet.add_argument("--modem-account", help="set modem account name (moUN)")
    internet.add_argument("--modem-password", help="set modem account password (moPW)")
    internet.add_argument("--modem-idle-seconds", type=int, help="set modem idle timeout (moID)")
    internet.add_argument("--modem-country-code", type=int, help="set modem country index (moCI)")
    internet.add_argument("--modem-protocol", choices=("v34", "v90"), help="set modem protocol (moMP)")
    internet.add_argument(
        "--modem-pulse-dialing", action=argparse.BooleanOptionalAction, default=None
    )
    internet.add_argument(
        "--modem-automatically-dial", action=argparse.BooleanOptionalAction, default=None
    )
    internet.add_argument(
        "--modem-ignore-dial-tone", action=argparse.BooleanOptionalAction, default=None
    )
    internet.add_argument(
        "--modem-use-aol", action=argparse.BooleanOptionalAction, default=None
    )
    add_advanced_arguments(parser)

    wireless = parser.add_argument_group("Wireless tab settings")
    wireless.add_argument(
        "--wireless-mode",
        choices=sorted(WIRELESS_MODE_VALUES),
        help="set Wireless Network Mode (raSt)",
    )
    wireless.add_argument("--wireless-name", help="set Wireless Network Name (raNm)")
    wireless.add_argument(
        "--wireless-security",
        choices=sorted(WIRELESS_SECURITY_VALUES),
        help="set Wireless Security (raWM)",
    )
    wireless.add_argument("--wireless-password", help="set Wireless Password (raCr/raWE)")
    wireless.add_argument(
        "--allow-network-extension",
        dest="allow_network_extension",
        action="store_true",
        default=None,
        help="allow this network to be extended (dWDS)",
    )
    wireless.add_argument(
        "--no-allow-network-extension",
        dest="allow_network_extension",
        action="store_false",
        help="do not allow this network to be extended (dWDS)",
    )
    wireless.add_argument(
        "--wds-peer-airport-id",
        action="append",
        help="set WDS peer AirPort ID list (wdLs); repeat or comma-separate",
    )
    wireless.add_argument(
        "--wds-mode",
        choices=sorted(WDS_MODE_VALUES),
        help="set WDS role (bsWM)",
    )
    wireless.add_argument("--region-code", type=int, help="set wireless Region code (syRe)")
    wireless.add_argument(
        "--hidden-network",
        dest="hidden_network",
        action="store_true",
        default=None,
        help="enable hidden network (raCl)",
    )
    wireless.add_argument(
        "--no-hidden-network",
        dest="hidden_network",
        action="store_false",
        help="disable hidden network (raCl)",
    )
    wireless.add_argument(
        "--radio-mode",
        choices=sorted(RADIO_MODE_VALUES),
        help="set Radio Mode (raMd)",
    )
    wireless.add_argument("--radio-channel", help="set Radio Channel (raCh)")

    airplay = parser.add_argument_group("AirPlay tab settings")
    airplay.add_argument(
        "--airplay-enabled",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="enable or disable AirPlay (auRR)",
    )
    airplay.add_argument("--airplay-speaker-name", help="set AirPlay Speaker Name (auNN)")
    airplay.add_argument("--airplay-speaker-password", help="set AirPlay Speaker Password (auNP)")
    airplay.add_argument(
        "--clear-airplay-speaker-password",
        action="store_true",
        help="clear AirPlay Speaker Password (auNP)",
    )
    airplay.add_argument(
        "--airplay-over-wan",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="enable or disable AirPlay over WAN (aWan)",
    )

    base_station = parser.add_argument_group("Base Station tab settings")
    base_station.add_argument(
        "--allow-setup-over-wan",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="enable or disable setup over the Ethernet WAN port (raWB)",
    )

    router = parser.add_argument_group("Network tab settings")
    router.add_argument(
        "--router-mode",
        choices=sorted(ROUTER_MODE_VALUES),
        help="set Router Mode (bsRM)",
    )
    router.add_argument("--dhcp-range-start", help="set DHCP Range beginning (dhBg)")
    router.add_argument("--dhcp-range-end", help="set DHCP Range ending (dhEn)")
    router.add_argument("--dhcp-lease", type=int, help="set DHCP Lease duration number (dhLe)")
    router.add_argument(
        "--dhcp-lease-unit",
        choices=sorted(DHCP_LEASE_UNITS),
        default="seconds",
        help="unit for --dhcp-lease; default: seconds",
    )
    router.add_argument(
        "--nat-pmp",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="enable or disable NAT Port Mapping Protocol (naFl)",
    )
    router.add_argument("--default-host", help="set default host IP address (nDMZ)")
    router.add_argument("--clear-default-host", action="store_true", help="clear default host (nDMZ)")
    return parser

def legacy_write_main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        provided_values = sum(
            value is not None for value in (args.value, args.value_json, args.values_json)
        )
        if provided_values > 1:
            raise ValueError("use only one of --value, --value-json, or --values-json")
        if args.setting is not None:
            if args.values_json is not None:
                raise ValueError("--setting cannot be combined with --values-json")
            if len(args.setting.encode("ascii", errors="ignore")) != 4 or len(args.setting) != 4:
                raise ValueError(f"setting names must be exactly 4 ASCII characters: {args.setting!r}")
            if args.value is None and args.value_json is None:
                raise ValueError("--value or --value-json is required with --setting")
        elif args.value is not None or args.value_json is not None:
            raise ValueError("--setting is required with --value or --value-json")

        dirty = build_dirty(args)
        if not dirty and not args.restart and not args.apply:
            raise ValueError("no settings were provided")

        if args.dry_run_json:
            apply = (args.restart or args.apply) and not args.no_apply
            sent_dirty = legacy_apply_dirty(dirty) if apply else dirty
            print(
                json.dumps(
                    normalized_legacy_write_intent(
                        args.host,
                        sent_dirty,
                        streaming=args.streaming or args.restart or args.apply,
                        apply=apply,
                        request_flags=args.request_flags,
                    ),
                    indent=2,
                    sort_keys=True,
                )
            )
            return 0

        if args.dry_run:
            sent_dirty = (
                legacy_apply_dirty(dirty)
                if (args.restart or args.apply) and not args.no_apply
                else dirty
            )
            result = {
                "changedKeys": sorted(sent_dirty),
                "apply": (args.restart or args.apply) and not args.no_apply,
                "restart": (args.restart or args.apply) and not args.no_apply,
            }
            if args.json:
                print(json.dumps(result, indent=2, sort_keys=True))
            else:
                print(f"DRY RUN legacy ACP accepted keys: {', '.join(sorted(sent_dirty))}.")
            return 0

        sent_dirty = (
            legacy_apply_dirty(dirty)
            if (args.restart or args.apply) and not args.no_apply
            else dirty
        )
        if args.acp17:
            statuses = send_property_write_streaming_acp17(
                args.host, args.password, sent_dirty, args.timeout, args.request_flags
            )
        elif args.streaming or ((args.restart or args.apply) and not args.no_apply):
            statuses = send_property_write_streaming(
                args.host, args.password, sent_dirty, args.timeout, args.request_flags
            )
        else:
            statuses = (
                send_property_write(
                    args.host,
                    args.password,
                    sent_dirty,
                    args.timeout,
                    args.request_flags,
                )
                if sent_dirty
                else []
            )
        result = {
            "changedKeys": sorted(sent_dirty),
            "apply": (args.restart or args.apply) and not args.no_apply,
            "restart": (args.restart or args.apply) and not args.no_apply,
            "statuses": statuses,
        }
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            print(f"legacy ACP accepted keys: {', '.join(sorted(dirty))}.")
        return 0
    except (ACPError, OSError, RuntimeError, ValueError, TypeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

def main() -> int:
    argv = sys.argv[1:]
    commands = {
        "read",
        "write",
        "property-write",
        "legacy-read",
        "legacy-write",
        "wireless-clients",
    }
    if argv and argv[0] not in commands:
        if "--restart" in argv:
            return legacy_write_main(argv)
        return modern_write_main(argv)

    parser = argparse.ArgumentParser(description="AirPort backend protocol utility.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in commands:
        subparsers.add_parser(command, add_help=False)
    namespace, remaining = parser.parse_known_args(argv)
    if namespace.command == "read":
        return modern_read_main(remaining)
    if namespace.command == "write":
        return modern_write_main(remaining)
    if namespace.command == "property-write":
        return modern_property_write_main(remaining)
    if namespace.command == "legacy-read":
        return legacy_read_main(remaining)
    if namespace.command == "legacy-write":
        return legacy_write_main(remaining)
    if namespace.command == "wireless-clients":
        return wireless_clients_main(remaining)
    parser.error(f"unknown command: {namespace.command}")
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
