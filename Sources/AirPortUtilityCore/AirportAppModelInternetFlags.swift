import Foundation

@MainActor
extension AirportAppModel {
  func internetFlags(changesOnly: Bool = false) -> [(String, String?)]? {
    var flags: [(String, String?)] = []
    let supportsIPv6Writes = showsIPv6InternetControls
    let supportsDynamicGlobalHostnameWrites = showsDynamicGlobalHostnameControls
    appendChanged(
      &flags, "--connect-using", internet.connectUsing.rawValue,
      cleanSnapshot.internet.connectUsing.rawValue, changesOnly: changesOnly)
    if supportsIPv6Writes {
      guard
        validateOption(
          internet.configureIPv6,
          cleanValue: cleanSnapshot.internet.configureIPv6,
          changesOnly: changesOnly,
          allowed: ["link-local", "automatic", "manual"],
          statusMessage: localized("Configure IPv6 must be link-local, automatic, or manual.")
        )
      else { return nil }
      guard
        validateOption(
          internet.ipv6Mode,
          cleanValue: cleanSnapshot.internet.ipv6Mode,
          changesOnly: changesOnly,
          allowed: ["host", "tunnel", "router"],
          statusMessage: localized("IPv6 Mode must be host, tunnel, or router."),
          allowEmpty: true
        )
      else { return nil }
    }
    if internet.connectUsing == .static {
      let staticModeChanged = internet.connectUsing != cleanSnapshot.internet.connectUsing
      let needsValidation = { (fieldChanged: Bool) in
        !changesOnly || staticModeChanged || fieldChanged
      }
      let ipv4AddressChanged =
        normalized(internet.ipv4Address) != normalized(cleanSnapshot.internet.ipv4Address)
      let subnetMaskChanged =
        normalized(internet.subnetMask) != normalized(cleanSnapshot.internet.subnetMask)
      let routerAddressChanged =
        normalized(internet.routerAddress) != normalized(cleanSnapshot.internet.routerAddress)
      guard !needsValidation(ipv4AddressChanged) || !normalized(internet.ipv4Address).isEmpty
      else {
        status = localized("IPv4 Address cannot be empty.")
        return nil
      }
      guard !needsValidation(ipv4AddressChanged) || isIPv4Address(internet.ipv4Address) else {
        status = localized("IPv4 Address must be an IPv4 address.")
        return nil
      }
      guard !needsValidation(subnetMaskChanged) || !normalized(internet.subnetMask).isEmpty
      else {
        status = localized("Subnet Mask cannot be empty.")
        return nil
      }
      if needsValidation(subnetMaskChanged),
        let validationError = subnetMaskValidationError(internet.subnetMask)
      {
        status = validationError
        return nil
      }
      guard !needsValidation(routerAddressChanged) || !normalized(internet.routerAddress).isEmpty
      else {
        status = localized("Router Address cannot be empty.")
        return nil
      }
      guard !needsValidation(routerAddressChanged) || isIPv4Address(internet.routerAddress) else {
        status = localized("Router Address must be an IPv4 address.")
        return nil
      }
      appendChanged(
        &flags, "--ipv4-address", internet.ipv4Address, cleanSnapshot.internet.ipv4Address,
        changesOnly: changesOnly)
      appendChanged(
        &flags, "--subnet-mask", internet.subnetMask, cleanSnapshot.internet.subnetMask,
        changesOnly: changesOnly)
      appendChanged(
        &flags, "--router-address", internet.routerAddress, cleanSnapshot.internet.routerAddress,
        changesOnly: changesOnly)
    } else if internet.connectUsing == .dhcp && cleanSnapshot.internet.connectUsing != .dhcp {
      flags.append(("--ipv4-address", "0.0.0.0"))
      flags.append(("--subnet-mask", "0.0.0.0"))
      flags.append(("--router-address", "0.0.0.0"))
    }
    let cleanDNSServersForDiff =
      cleanSnapshot.internet.connectUsing == .dhcp
      && internet.connectUsing != .dhcp
      && internet.connectUsing != .static
      && !normalized(cleanSnapshot.internet.dnsServerPreview).isEmpty
      ? cleanSnapshot.internet.dnsServerPreview : cleanSnapshot.internet.dnsServers
    let cleanIPv6DNSServersForDiff =
      cleanSnapshot.internet.connectUsing == .dhcp
      && internet.connectUsing != .dhcp
      && internet.connectUsing != .static
      && !normalized(cleanSnapshot.internet.ipv6DNSServerPreview).isEmpty
      ? cleanSnapshot.internet.ipv6DNSServerPreview : cleanSnapshot.internet.ipv6DNSServers
    guard
      appendAddressList(
        &flags,
        valueFlag: "--dns-server",
        clearFlag: "--clear-dns",
        value: internet.dnsServers,
        cleanValue: cleanDNSServersForDiff,
        changesOnly: changesOnly,
        maxCount: 2,
        countError: localized("DNS Servers accepts at most two IPv4 DNS servers."),
        emptyValueError: localized("DNS Servers contains an empty value."),
        validator: isIPv4Address,
        validationError: localized("DNS Server must be an IPv4 address."),
        slotValueFlags: ["--dns-server-1", "--dns-server-2"]
      )
    else { return nil }
    if supportsIPv6Writes {
      guard
        appendAddressList(
          &flags,
          valueFlag: "--ipv6-dns-server",
          clearFlag: "--clear-ipv6-dns",
          value: internet.ipv6DNSServers,
          cleanValue: cleanIPv6DNSServersForDiff,
          changesOnly: changesOnly,
          maxCount: 2,
          countError: localized("IPv6 DNS Servers accepts at most two IPv6 DNS servers."),
          emptyValueError: localized("IPv6 DNS Servers contains an empty value."),
          validator: isIPv6Address,
          validationError: localized("IPv6 DNS Server must be an IPv6 address."),
          normalizer: normalizedIPv6Address
        )
      else { return nil }
    }
    appendChanged(
      &flags, "--domain-name", internet.domainName, cleanSnapshot.internet.domainName,
      changesOnly: changesOnly)
    if supportsIPv6Writes
      && (!changesOnly
        || normalizedIPv6Address(internet.ipv6Address)
          != normalizedIPv6Address(cleanSnapshot.internet.ipv6Address))
    {
      let ipv6Address = normalizedIPv6Address(internet.ipv6Address)
      if !ipv6Address.isEmpty {
        guard isIPv6Address(ipv6Address) else {
          status = localized("IPv6 Address must be an IPv6 address.")
          return nil
        }
        flags.append(("--ipv6-address", ipv6Address))
      }
    }
    if internet.connectUsing == .pppoe {
      let pppoeModeChanged = internet.connectUsing != cleanSnapshot.internet.connectUsing
      let pppoeAccountChanged =
        normalized(internet.pppoeAccount) != normalized(cleanSnapshot.internet.pppoeAccount)
      let shouldValidatePPPoEAccount =
        !changesOnly || pppoeModeChanged || pppoeAccountChanged
      guard
        validateOption(
          internet.pppoeConnection,
          cleanValue: cleanSnapshot.internet.pppoeConnection,
          changesOnly: changesOnly,
          allowed: ["always-on", "automatic", "manual"],
          statusMessage: localized("PPPoE Connection must be always-on, automatic, or manual.")
        )
      else { return nil }
      guard !shouldValidatePPPoEAccount || !normalized(internet.pppoeAccount).isEmpty else {
        status = localized("PPPoE Account Name cannot be empty.")
        return nil
      }
      appendChanged(
        &flags, "--pppoe-account", internet.pppoeAccount, cleanSnapshot.internet.pppoeAccount,
        changesOnly: changesOnly && !pppoeModeChanged)
      appendChanged(
        &flags, "--pppoe-password", internet.pppoePassword, cleanSnapshot.internet.pppoePassword,
        changesOnly: changesOnly && !pppoeModeChanged)
      appendChanged(
        &flags, "--pppoe-service", internet.pppoeService, cleanSnapshot.internet.pppoeService,
        changesOnly: changesOnly && !pppoeModeChanged)
      appendChanged(
        &flags, "--pppoe-connection", internet.pppoeConnection,
        cleanSnapshot.internet.pppoeConnection, changesOnly: changesOnly)
    }
    if internet.connectUsing == .modem {
      guard showsModemControls else {
        status = localized("This base station does not support a modem connection.")
        return nil
      }
      let modemModeChanged = cleanSnapshot.internet.connectUsing != .modem
      guard internet.modemPassword == internet.modemVerifyPassword else {
        status = localized("Modem passwords do not match.")
        return nil
      }
      let diffOnly = changesOnly && !modemModeChanged
      appendChanged(
        &flags, "--modem-phone-number", internet.modemPhoneNumber,
        cleanSnapshot.internet.modemPhoneNumber, changesOnly: diffOnly)
      appendChanged(
        &flags, "--modem-alternate-number", internet.modemAlternateNumber,
        cleanSnapshot.internet.modemAlternateNumber, changesOnly: diffOnly)
      appendChanged(
        &flags, "--modem-account", internet.modemAccount,
        cleanSnapshot.internet.modemAccount, changesOnly: diffOnly)
      appendChanged(
        &flags, "--modem-password", internet.modemPassword,
        cleanSnapshot.internet.modemPassword, changesOnly: diffOnly)
      appendChanged(
        &flags, "--modem-idle-seconds", String(internet.modemIdleSeconds),
        String(cleanSnapshot.internet.modemIdleSeconds), changesOnly: diffOnly)
      appendChanged(
        &flags, "--modem-country-code", String(internet.modemCountryCode),
        String(cleanSnapshot.internet.modemCountryCode), changesOnly: diffOnly)
      appendChanged(
        &flags, "--modem-protocol", internet.modemProtocol,
        cleanSnapshot.internet.modemProtocol, changesOnly: diffOnly)
      appendChangedBoolean(
        &flags,
        trueFlag: "--modem-pulse-dialing",
        falseFlag: "--no-modem-pulse-dialing",
        value: internet.modemPulseDialing,
        cleanValue: cleanSnapshot.internet.modemPulseDialing,
        changesOnly: diffOnly)
      appendChangedBoolean(
        &flags,
        trueFlag: "--modem-automatically-dial",
        falseFlag: "--no-modem-automatically-dial",
        value: internet.modemAutomaticallyDial,
        cleanValue: cleanSnapshot.internet.modemAutomaticallyDial,
        changesOnly: diffOnly)
      appendChangedBoolean(
        &flags,
        trueFlag: "--modem-ignore-dial-tone",
        falseFlag: "--no-modem-ignore-dial-tone",
        value: internet.modemIgnoreDialTone,
        cleanValue: cleanSnapshot.internet.modemIgnoreDialTone,
        changesOnly: diffOnly)
      appendChangedBoolean(
        &flags,
        trueFlag: "--modem-use-aol",
        falseFlag: "--no-modem-use-aol",
        value: internet.modemUseAOL,
        cleanValue: cleanSnapshot.internet.modemUseAOL,
        changesOnly: diffOnly)
    } else if cleanSnapshot.internet.connectUsing == .modem {
      flags += [
        ("--modem-phone-number", ""),
        ("--modem-alternate-number", ""),
        ("--modem-account", ""),
        ("--modem-password", ""),
        ("--modem-idle-seconds", "600"),
        ("--modem-country-code", "0"),
        ("--modem-protocol", "v34"),
        ("--no-modem-pulse-dialing", nil),
        ("--modem-automatically-dial", nil),
        ("--no-modem-ignore-dial-tone", nil),
        ("--no-modem-use-aol", nil),
      ]
    }
    if supportsIPv6Writes {
      appendChanged(
        &flags, "--configure-ipv6", internet.configureIPv6, cleanSnapshot.internet.configureIPv6,
        changesOnly: changesOnly)
      appendChanged(
        &flags, "--ipv6-mode", internet.ipv6Mode, cleanSnapshot.internet.ipv6Mode,
        changesOnly: changesOnly)
      appendChanged(
        &flags, "--ipv6-default-route", internet.ipv6DefaultRoute,
        cleanSnapshot.internet.ipv6DefaultRoute, changesOnly: changesOnly)
      if internet.ipv6Firewall || cleanSnapshot.internet.ipv6Firewall {
        appendChangedBoolean(
          &flags,
          trueFlag: "--ipv6-firewall",
          falseFlag: "--no-ipv6-firewall",
          value: internet.ipv6Firewall,
          cleanValue: cleanSnapshot.internet.ipv6Firewall,
          changesOnly: changesOnly
        )
      }
    }
    if supportsDynamicGlobalHostnameWrites {
      appendChangedBoolean(
        &flags,
        trueFlag: "--dynamic-global-hostname",
        falseFlag: "--no-dynamic-global-hostname",
        value: internet.dynamicGlobalHostname,
        cleanValue: cleanSnapshot.internet.dynamicGlobalHostname,
        changesOnly: changesOnly
      )
      if internet.dynamicGlobalHostnameAutoConfig
        || cleanSnapshot.internet.dynamicGlobalHostnameAutoConfig
      {
        appendChangedBoolean(
          &flags,
          trueFlag: "--dynamic-global-hostname-auto-config",
          falseFlag: "--no-dynamic-global-hostname-auto-config",
          value: internet.dynamicGlobalHostnameAutoConfig,
          cleanValue: cleanSnapshot.internet.dynamicGlobalHostnameAutoConfig,
          changesOnly: changesOnly
        )
      }
    }
    if supportsDynamicGlobalHostnameWrites && internet.dynamicGlobalHostname {
      let dynamicGlobalHostnameChanged =
        internet.dynamicGlobalHostname != cleanSnapshot.internet.dynamicGlobalHostname
      let globalHostnameChanged =
        normalized(internet.globalHostname) != normalized(cleanSnapshot.internet.globalHostname)
      let shouldValidateGlobalHostname =
        !changesOnly || dynamicGlobalHostnameChanged || globalHostnameChanged
      guard !shouldValidateGlobalHostname || !normalized(internet.globalHostname).isEmpty else {
        status = localized("Global Hostname cannot be empty.")
        return nil
      }
      appendChanged(
        &flags, "--global-hostname", internet.globalHostname, cleanSnapshot.internet.globalHostname,
        changesOnly: changesOnly)
      appendChanged(
        &flags, "--global-hostname-user", internet.globalHostnameUser,
        cleanSnapshot.internet.globalHostnameUser, changesOnly: changesOnly)
      appendChanged(
        &flags, "--global-hostname-password", internet.globalHostnamePassword,
        cleanSnapshot.internet.globalHostnamePassword, changesOnly: changesOnly)
    }
    return flags
  }

}
