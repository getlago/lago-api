# frozen_string_literal: true

module SolanaTransactionBuilder
  TOKEN_PROGRAM = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
  TOKEN_2022_PROGRAM = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
  SYSTEM_PROGRAM = "11111111111111111111111111111111"

  def build_solana_transaction(keys:, instructions:, signatures:, required_signatures: signatures.size,
    readonly_signed: 0, readonly_unsigned: 0, version: 0, lookups: [], blockhash: "\x07".b * 32)
    message = +"".b
    message << (0x80 | version).chr if version
    message << [required_signatures, readonly_signed, readonly_unsigned].pack("C3")
    message << compact_u16(keys.size) << keys.map { |key| X402::Base58.decode(key) }.join
    message << blockhash
    message << compact_u16(instructions.size)
    instructions.each do |instruction|
      message << [instruction[:program]].pack("C")
      message << compact_u16(instruction[:accounts].size) << instruction[:accounts].pack("C*")
      message << compact_u16(instruction[:data].bytesize) << instruction[:data].b
    end
    if version
      message << compact_u16(lookups.size)
      lookups.each do |lookup|
        message << X402::Base58.decode(lookup[:table])
        message << compact_u16(lookup[:writable].size) << lookup[:writable].pack("C*")
        message << compact_u16(lookup[:readonly].size) << lookup[:readonly].pack("C*")
      end
    end

    compact_u16(signatures.size) + signatures.join.b + message
  end

  def transfer_checked_data(amount, decimals: 6)
    [12, amount, decimals].pack("CQ<C")
  end

  def compact_u16(value)
    bytes = []
    loop do
      byte = value & 0x7f
      value >>= 7
      break bytes << byte if value.zero?

      bytes << (byte | 0x80)
    end
    bytes.pack("C*")
  end
end
