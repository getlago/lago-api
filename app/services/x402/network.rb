# frozen_string_literal: true

module X402
  # §10: the chain-family value object. D5: EVM addresses are stored and compared in EIP-55 form.
  module Network
    EVM_ADDRESS_FORMAT = /\A0x[0-9a-fA-F]{40}\z/

    module_function

    def family_of_network(network)
      case network.to_s.split(":", 2).first
      when "eip155" then :evm
      when "solana" then :svm
      else raise ArgumentError, "Unsupported x402 network: #{network.inspect}"
      end
    end

    def evm_chain_id(network)
      Integer(network.to_s.delete_prefix("eip155:"))
    end

    # Keccak-256 is not SHA3-256 (different padding); OpenSSL >= 3.2 ships Ethereum's variant as KECCAK-256.
    def checksum(address)
      raise ArgumentError, "Not an EVM address: #{address.inspect}" unless EVM_ADDRESS_FORMAT.match?(address.to_s)

      hex = address.to_s.delete_prefix("0x").downcase
      digest = OpenSSL::Digest.new("KECCAK-256").hexdigest(hex)
      checksummed = hex.chars.each_with_index.map { |char, index| (digest[index].to_i(16) >= 8) ? char.upcase : char }
      "0x#{checksummed.join}"
    end
  end
end
