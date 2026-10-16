# frozen_string_literal: true

module X402
  module Secp256k1
    GROUP = OpenSSL::PKey::EC::Group.new("secp256k1").freeze
    ORDER = GROUP.order.to_i
    SIGNATURE_SIZE = 65
    DIGEST_SIZE = 32

    def self.recover_public_key(digest:, signature:)
      digest = digest.to_s.b
      signature = signature.to_s.b
      return nil unless digest.bytesize == DIGEST_SIZE && signature.bytesize == SIGNATURE_SIZE

      recid = recovery_id(signature.getbyte(64))
      r = signature.byteslice(0, 32).unpack1("H*").to_i(16)
      s = signature.byteslice(32, 32).unpack1("H*").to_i(16)
      return nil unless recid && r.between?(1, ORDER - 1) && s.between?(1, ORDER - 1)

      recover(digest.unpack1("H*").to_i(16), r, s, recid)
    end

    def self.recovery_id(v)
      if [0, 1].include?(v)
        v
      elsif [27, 28].include?(v)
        v - 27
      end
    end

    def self.recover(z, r, s, recid)
      r_point = OpenSSL::PKey::EC::Point.new(GROUP, [format("%02x%064x", 2 | recid, r)].pack("H*"))
      r_inverse = r.pow(ORDER - 2, ORDER)
      point = r_point.mul(OpenSSL::BN.new((s * r_inverse) % ORDER), OpenSSL::BN.new(((ORDER - z) * r_inverse) % ORDER))

      if point.infinity?
        nil
      else
        point.to_octet_string(:uncompressed)
      end
    rescue OpenSSL::PKey::EC::Point::Error
      nil
    end

    private_class_method :recovery_id, :recover
  end
end
