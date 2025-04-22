# frozen_string_literal: true

module IdempotencyRecords
  class KeyService < BaseService
    Result = BaseResult[:idempotency_key]
    def initialize(*key_parts)
      @key_parts = key_parts

      super()
    end

    def call
      string_to_digest = key_parts.map(&:to_s).join
      result.idempotency_key = Digest::SHA256.digest(string_to_digest)
      result
    end

    private

    attr_reader :key_parts
  end
end
