# frozen_string_literal: true

require "ipaddr"
require "socket"

module LagoHttpClient
  module AddressGuard
    BLOCKED_RANGES = [
      # IPv4
      "0.0.0.0/8",
      "10.0.0.0/8",
      "100.64.0.0/10",
      "127.0.0.0/8",
      "169.254.0.0/16",
      "172.16.0.0/12",
      "192.0.0.0/24",
      "192.0.2.0/24",
      "192.88.99.0/24",
      "192.168.0.0/16",
      "198.18.0.0/15",
      "198.51.100.0/24",
      "203.0.113.0/24",
      "224.0.0.0/4",
      "240.0.0.0/4",
      # IPv6 special-purpose ranges inside global unicast
      "2001::/23",
      "2001:db8::/32",
      "2002::/16",
      "3fff::/20"
    ].map { |range| IPAddr.new(range) }.freeze

    # Anything outside global unicast (loopback, mapped IPv4, ULA, link-local, SRv6, multicast...) is blocked.
    IPV6_GLOBAL_UNICAST = IPAddr.new("2000::/3").freeze
    # DNS64 synthesizes these for IPv4-only hosts, so the embedded IPv4 address is what gets checked.
    NAT64_WELL_KNOWN_PREFIX = IPAddr.new("64:ff9b::/96").freeze

    def self.enabled?
      !ActiveModel::Type::Boolean.new.cast(ENV["LAGO_WEBHOOK_ALLOW_PRIVATE_URLS"])
    end

    # Raises SocketError when the host does not resolve.
    def self.resolve!(host)
      addresses = Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
      raise SocketError, "getaddrinfo: no address for #{host}" if addresses.empty?
      raise BlockedAddressError, host if addresses.any? { |address| blocked_ip?(address) }

      addresses.first
    end

    def self.blocked_ip?(address)
      ip = IPAddr.new(address)
      ip = IPAddr.new(ip.to_i & 0xffff_ffff, Socket::AF_INET) if NAT64_WELL_KNOWN_PREFIX.include?(ip)
      return true if ip.ipv6? && !IPV6_GLOBAL_UNICAST.include?(ip)

      BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
    end
  end
end
