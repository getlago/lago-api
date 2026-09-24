# frozen_string_literal: true

require "openssl"

module X402Poc
  # Signs an EIP-3009 TransferWithAuthorization (EIP-712 typed data) with a secp256k1 key. Lago never does this:
  # the agent does. Validated against the EIP-712 spec vector (digest, address, signer recovery) on 2026-09-24.
  class Eip3009Signer
    CURVE = OpenSSL::PKey::EC::Group.new("secp256k1")
    ORDER = CURVE.order.to_i
    DOMAIN_TYPE = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    TRANSFER_TYPE = "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"

    attr_reader :address

    def initialize(private_key_hex)
      @key = build_key(private_key_hex.to_s.delete_prefix("0x"))
      public_bytes = key.public_key.to_octet_string(:uncompressed).byteslice(1..)
      @address = X402::Network.checksum("0x#{keccak(public_bytes).byteslice(-20..).unpack1("H*")}")
    end

    # 65-byte r ‖ s ‖ v as 0x-hex, low-s normalised (EIP-2), v in {27, 28}.
    def sign_transfer_with_authorization(domain:, message:)
      digest = keccak("\x19\x01".b + domain_separator(domain) + struct_hash(message))
      r, s = OpenSSL::ASN1.decode(key.sign_raw(nil, digest)).value.map { |part| part.value.to_i }
      s = ORDER - s if s > ORDER / 2

      "0x#{hex32(r)}#{hex32(s)}#{(27 + recovery_id(digest, r, s)).to_s(16)}"
    end

    private

    attr_reader :key

    def domain_separator(domain)
      keccak(keccak(DOMAIN_TYPE) + keccak(domain.fetch(:name)) + keccak(domain.fetch(:version)) +
        uint256(domain.fetch(:chain_id)) + address32(domain.fetch(:verifying_contract)))
    end

    def struct_hash(message)
      keccak(keccak(TRANSFER_TYPE) + address32(message.fetch("from")) + address32(message.fetch("to")) +
        uint256(message.fetch("value")) + uint256(message.fetch("validAfter")) + uint256(message.fetch("validBefore")) +
        [message.fetch("nonce").delete_prefix("0x")].pack("H*"))
    end

    # The v that makes ecrecover return this key: Q = r⁻¹(sR − eG), tried for both parities of R.
    def recovery_id(digest, r, s)
      e = digest.unpack1("H*").to_i(16)
      r_inverse = r.pow(ORDER - 2, ORDER)
      parity = [0, 1].find do |candidate|
        point = OpenSSL::PKey::EC::Point.new(CURVE, OpenSSL::BN.new("#{candidate.zero? ? "02" : "03"}#{hex32(r)}", 16))
        point.mul(OpenSSL::BN.new((s * r_inverse) % ORDER), OpenSSL::BN.new(((ORDER - e) * r_inverse) % ORDER)) == key.public_key
      end

      parity || raise("Could not derive the recovery id")
    end

    def build_key(private_hex)
      public_point = CURVE.generator.mul(OpenSSL::BN.new(private_hex, 16))

      OpenSSL::PKey::EC.new(OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::Integer(1),
        OpenSSL::ASN1::OctetString([private_hex.rjust(64, "0")].pack("H*")),
        OpenSSL::ASN1::ObjectId("secp256k1", 0, :EXPLICIT),
        OpenSSL::ASN1::BitString(public_point.to_octet_string(:uncompressed), 1, :EXPLICIT)
      ]).to_der)
    end

    def keccak(data) = OpenSSL::Digest.new("KECCAK-256").digest(data)

    def uint256(value) = [Integer(value).to_s(16).rjust(64, "0")].pack("H*")

    def address32(value) = [value.delete_prefix("0x").rjust(64, "0")].pack("H*")

    def hex32(value) = value.to_s(16).rjust(64, "0")
  end
end
