# frozen_string_literal: true

module X402
  class Asset < Data.define(:code, :network, :address, :decimals, :eip712_name, :eip712_version)
    DEFINITIONS = [
      new(code: "usdc", network: "eip155:8453", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", decimals: 6, eip712_name: "USD Coin", eip712_version: "2"),
      new(code: "usdc", network: "eip155:84532", address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", decimals: 6, eip712_name: "USDC", eip712_version: "2"),
      new(code: "usdc", network: "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", address: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 6, eip712_name: nil, eip712_version: nil),
      new(code: "usdc", network: "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1", address: "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU", decimals: 6, eip712_name: nil, eip712_version: nil)
    ].index_by { |asset| [asset.code, asset.network] }.freeze

    def self.fetch(code:, network:)
      DEFINITIONS.fetch([code.to_s, network.to_s])
    end

    def atomic_units_per_cent
      10**(decimals - 2)
    end

    def cents_from_atomic(atomic)
      unsigned(atomic) / atomic_units_per_cent
    end

    def atomic_from_cents(cents)
      unsigned(cents) * atomic_units_per_cent
    end

    def eip712_domain
      return if eip712_name.nil?

      {"name" => eip712_name, "version" => eip712_version}
    end

    private

    def unsigned(value)
      UnsignedInteger.parse(value) || raise(ArgumentError, "not an unsigned integer: #{value.inspect}")
    end
  end
end
