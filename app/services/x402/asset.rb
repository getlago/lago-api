# frozen_string_literal: true

module X402
  # The stablecoin per CAIP-2 network. The EIP-712 domain is what the payer signs against (EIP-3009):
  # a wrong name or version yields a signature the facilitator rejects with no useful error.
  class Asset < Data.define(:code, :network, :address, :decimals, :eip712_name, :eip712_version)
    DEFINITIONS = [
      new(code: "usdc", network: "eip155:8453", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", decimals: 6, eip712_name: "USD Coin", eip712_version: "2"),
      new(code: "usdc", network: "eip155:84532", address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", decimals: 6, eip712_name: "USDC", eip712_version: "2")
    ].index_by { |asset| [asset.code, asset.network] }.freeze

    def self.fetch(code:, network:)
      DEFINITIONS.fetch([code.to_s, network])
    end

    # D11: 10 ** (decimals - 2), not a hardcoded 10_000.
    def atomic_units_per_cent
      10**(decimals - 2)
    end
  end
end
