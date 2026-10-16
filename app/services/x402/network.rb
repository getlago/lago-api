# frozen_string_literal: true

module X402
  module Network
    FAMILIES = {"eip155" => :evm, "solana" => :svm}.freeze

    NETWORKS = {
      "eip155:8453" => :mainnet,
      "eip155:84532" => :testnet,
      "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp" => :mainnet,
      "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" => :testnet
    }.freeze

    EVM_ADDRESS = /\A0x\h{40}\z/
    SVM_ADDRESS_BYTES = 32

    def self.family_of_network(network)
      if NETWORKS.key?(network.to_s)
        FAMILIES.fetch(network.to_s.split(":", 2).first)
      else
        raise ArgumentError, "unsupported x402 network: #{network.inspect}"
      end
    end

    def self.family_of_address(address)
      if EVM_ADDRESS.match?(address.to_s)
        :evm
      elsif Base58.decode(address)&.bytesize == SVM_ADDRESS_BYTES
        :svm
      end
    end

    def self.checksum(address)
      raise ArgumentError, "not an EVM address: #{address.inspect}" unless EVM_ADDRESS.match?(address.to_s)

      hex = address.to_s.delete_prefix("0x").downcase
      digest = Keccak256.hexdigest(hex)
      checksummed = hex.each_char.with_index.map { |char, index| (digest[index].to_i(16) >= 8) ? char.upcase : char }

      "0x#{checksummed.join}"
    end

    def self.valid_address?(address, family:)
      case family
      when :evm then valid_evm_address?(address.to_s)
      when :svm then Base58.decode(address)&.bytesize == SVM_ADDRESS_BYTES
      else raise ArgumentError, "unknown chain family: #{family.inspect}"
      end
    end

    def self.normalize_address(address, family:)
      return address unless family == :evm && valid_address?(address, family:)

      checksum(address)
    end

    def self.environment(network)
      NETWORKS.fetch(network.to_s) { raise ArgumentError, "unsupported x402 network: #{network.inspect}" }
    end

    def self.valid_evm_address?(address)
      return false unless EVM_ADDRESS.match?(address)

      hex = address.delete_prefix("0x")
      hex == hex.downcase || hex == hex.upcase || checksum(address) == address
    end
    private_class_method :valid_evm_address?
  end
end
