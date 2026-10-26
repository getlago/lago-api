# frozen_string_literal: true

module X402
  module Ed25519
    PUBLIC_KEY_SIZE = 32
    SIGNATURE_SIZE = 64

    SMALL_ORDER_KEYS = %w[
      0000000000000000000000000000000000000000000000000000000000000000
      0100000000000000000000000000000000000000000000000000000000000000
      26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05
      c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a
      ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f
      edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f
      eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f
    ].freeze

    SMALL_ORDER_POINTS = SMALL_ORDER_KEYS.map { |hex| [hex].pack("H*").freeze }.freeze

    def self.verify?(public_key:, signature:, message:)
      if [public_key, signature, message].all?(String)
        public_key = public_key.b
        signature = signature.b

        if public_key.bytesize == PUBLIC_KEY_SIZE && signature.bytesize == SIGNATURE_SIZE && !small_order?(public_key)
          OpenSSL::PKey.new_raw_public_key("ED25519", public_key).verify(nil, signature, message)
        else
          false
        end
      else
        false
      end
    rescue OpenSSL::PKey::PKeyError
      false
    end

    def self.small_order?(public_key)
      SMALL_ORDER_POINTS.any? do |entry|
        public_key.byteslice(0, 31) == entry.byteslice(0, 31) && (public_key.getbyte(31) & 0x7f) == entry.getbyte(31)
      end
    end

    private_class_method :small_order?
  end
end
