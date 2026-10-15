# frozen_string_literal: true

module X402
  module Base58
    ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    FORMAT = /\A[1-9A-HJ-NP-Za-km-z]+\z/

    def self.encode(bytes)
      bytes = bytes.b
      number = bytes.empty? ? 0 : bytes.unpack1("H*").to_i(16)
      encoded = +""

      while number.positive?
        number, remainder = number.divmod(58)
        encoded.prepend(ALPHABET[remainder])
      end

      ("1" * bytes.each_byte.take_while(&:zero?).size) + encoded
    end

    def self.decode(string)
      return unless string.is_a?(String) && FORMAT.match?(string)

      number = string.each_char.reduce(0) { |acc, char| (acc * 58) + ALPHABET.index(char) }
      hex = number.zero? ? "" : number.to_s(16)
      hex = "0#{hex}" if hex.size.odd?

      ("\x00" * string[/\A1*/].size).b + [hex].pack("H*")
    end
  end
end
