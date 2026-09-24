# frozen_string_literal: true

module X402
  # §5.2, §6.2: the idempotency key of a payment attempt. EVM: network, asset contract and the six
  # authorization fields, normalised; the envelope and the signature are ignored.
  module PaymentDigest
    module_function

    def evm(network:, asset:, authorization:)
      canonical = [
        network,
        Network.checksum(asset),
        Network.checksum(authorization.fetch("from")),
        Network.checksum(authorization.fetch("to")),
        Integer(authorization.fetch("value")),
        Integer(authorization.fetch("validAfter")),
        Integer(authorization.fetch("validBefore")),
        authorization.fetch("nonce").downcase
      ].join("|")

      OpenSSL::Digest::SHA256.hexdigest(canonical)
    end
  end
end
