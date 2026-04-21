# frozen_string_literal: true

module Quotes
  class VoidService < BaseService
    Result = BaseResult[:quote]

    def initialize(quote:, reason:)
      @quote = quote
      @reason = reason
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.forbidden_failure! unless quote.organization.feature_flag_enabled?(:quote)
      return result.single_validation_failure!(error_code: "invalid_void_reason", field: :reason) unless valid_reason?(reason)
      return result.not_allowed_failure!(code: "inappropriate_state") unless voidable?

      quote.update!(
        status: :voided,
        void_reason: reason,
        voided_at: Time.current
      )

      result.quote = quote
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :quote, :reason

    def voidable?
      quote.draft? || quote.approved?
    end

    def valid_reason?(value)
      return false if value.blank?

      Quote::VOID_REASONS.key?(value.to_s.to_sym)
    end
  end
end
