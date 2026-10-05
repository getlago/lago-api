# frozen_string_literal: true

module X402
  module Keccak256
    RATE = 136
    MASK = (1 << 64) - 1

    ROUND_CONSTANTS = [
      0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
      0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
      0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
      0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
      0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
      0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    ].freeze

    ROTATIONS = [0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14].freeze

    def self.hexdigest(message)
      digest(message).unpack1("H*")
    end

    def self.digest(message)
      state = Array.new(25, 0)

      pad(message.to_s.b).unpack("Q<*").each_slice(RATE / 8) do |lanes|
        lanes.each_with_index { |lane, index| state[index] ^= lane }
        permute(state)
      end

      state.first(4).pack("Q<4")
    end

    def self.pad(message)
      padded = message + ("\x00" * (RATE - (message.bytesize % RATE))).b
      padded.setbyte(message.bytesize, padded.getbyte(message.bytesize) | 0x01)
      padded.setbyte(padded.bytesize - 1, padded.getbyte(padded.bytesize - 1) | 0x80)
      padded
    end

    def self.permute(state)
      moved = Array.new(25, 0)

      ROUND_CONSTANTS.each do |round_constant|
        parities = Array.new(5) { |x| state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20] }
        25.times { |i| state[i] ^= parities[(i - 1) % 5] ^ rotate(parities[(i + 1) % 5], 1) }

        25.times do |i|
          x = i % 5
          y = i / 5
          moved[y + (5 * (((2 * x) + (3 * y)) % 5))] = rotate(state[i], ROTATIONS[i])
        end

        25.times do |i|
          row = 5 * (i / 5)
          state[i] = moved[i] ^ (~moved[row + (((i % 5) + 1) % 5)] & moved[row + (((i % 5) + 2) % 5)])
        end

        state[0] ^= round_constant
      end
    end

    def self.rotate(lane, bits)
      return lane if bits.zero?

      ((lane << bits) | (lane >> (64 - bits))) & MASK
    end

    private_class_method :pad, :permute, :rotate
  end
end
