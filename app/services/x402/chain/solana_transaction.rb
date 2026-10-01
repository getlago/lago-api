# frozen_string_literal: true

module X402
  module Chain
    class SolanaTransaction < Data.define(
      :signatures, :version, :num_required_signatures, :account_keys, :recent_blockhash, :instructions, :address_table_lookups
    )
      Instruction = Data.define(:program_id_index, :accounts, :data)

      TOKEN_PROGRAMS = %w[TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb].map { |key| Base58.decode(key) }.freeze
      SYSTEM_PROGRAM = ("\x00" * 32).b
      TRANSFER_CHECKED = 12
      ADVANCE_NONCE_ACCOUNT = [4].pack("L<")
      UNSUPPORTED_VERSION = "only legacy and v0 Solana transactions are readable"

      def self.decode(bytes)
        Reader.new(bytes).transaction
      end

      def transfer_checked
        instructions.find do |instruction|
          TOKEN_PROGRAMS.include?(account_keys[instruction.program_id_index]) && instruction.data.getbyte(0) == TRANSFER_CHECKED
        end
      end

      def signature_for(key)
        index = account_keys.index(key)
        signatures[index] if index && index < num_required_signatures
      end

      def durable_nonce?
        first = instructions.first
        first.present? && account_keys[first.program_id_index] == SYSTEM_PROGRAM && first.data.start_with?(ADVANCE_NONCE_ACCOUNT)
      end

      class Reader
        def initialize(bytes)
          @bytes = bytes.b
          @offset = 0
        end

        def transaction
          raise UnreadablePaymentError, UNSUPPORTED_VERSION unless (peek & 0x80).zero?

          signatures = Array.new(compact_u16) { read(64) }
          version = ((peek & 0x80).zero? ? :legacy : (byte & 0x7f))
          raise UnreadablePaymentError, UNSUPPORTED_VERSION unless [:legacy, 0].include?(version)

          num_required_signatures, = read(3).bytes
          account_keys = Array.new(compact_u16) { read(32) }
          recent_blockhash = read(32)
          instructions = Array.new(compact_u16) do
            Instruction.new(program_id_index: byte, accounts: read(compact_u16).bytes, data: read(compact_u16))
          end
          lookups = (version == :legacy) ? [] : Array.new(compact_u16) { lookup }
          raise UnreadablePaymentError, "trailing bytes after the Solana transaction" unless @offset == @bytes.bytesize

          SolanaTransaction.new(signatures:, version:, num_required_signatures:, account_keys:, recent_blockhash:, instructions:, address_table_lookups: lookups)
        end

        private

        def lookup
          {account_key: read(32), writable_indexes: read(compact_u16).bytes, readonly_indexes: read(compact_u16).bytes}
        end

        def compact_u16
          value = 0
          3.times do |shift|
            current = byte
            value |= (current & 0x7f) << (7 * shift)
            return value if (current & 0x80).zero?
          end
          raise UnreadablePaymentError, "invalid compact-u16 in the Solana transaction"
        end

        def read(size)
          raise UnreadablePaymentError, "truncated Solana transaction" if @offset + size > @bytes.bytesize

          chunk = @bytes.byteslice(@offset, size)
          @offset += size
          chunk
        end

        def byte
          read(1).ord
        end

        def peek
          raise UnreadablePaymentError, "truncated Solana transaction" if @offset >= @bytes.bytesize

          @bytes.getbyte(@offset)
        end
      end
      private_constant :Reader
    end
  end
end
