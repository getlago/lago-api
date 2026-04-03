# frozen_string_literal: true

module Quotes
  class VoidService < BaseService
    attr_reader :quote, :reason

    def initialize(quote:, reason:)
      @quote = quote
      @reason = reason
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.validation_failure!(errors: {quote: ["inappropriate_state"]}) unless voidable?
      return result.validation_failure!(errors: {quote: ["invalid_void_reason"]}) unless is_valid?(reason:)

      quote.update!(
        status: :voided,
        void_reason: reason,
        voided_at: Time.current,
        share_token: nil
      )
      result.quote = quote
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def voidable?
      quote.approved? || quote.draft?
    end

    def is_valid?(reason:)
      return false if reason.blank?

      Quote::VOID_REASONS.has_key?(reason.to_sym)
    end
  end
end
