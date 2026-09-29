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
      # IPv6
      "::/128",
      "::1/128",
      "::ffff:0:0/96",
      "64:ff9b:1::/48",
      "100::/64",
      "2001::/23",
      "2001:db8::/32",
      "2002::/16",
      "fc00::/7",
      "fe80::/10",
      "fec0::/10",
      "ff00::/8"
    ].map { |range| IPAddr.new(range) }.freeze

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
      BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
    end
  end
end
