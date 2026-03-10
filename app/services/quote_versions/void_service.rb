# frozen_string_literal: true

module QuoteVersions
  class VoidService < BaseService
    attr_reader :quote_version, :reason

    Result = BaseResult[:quote_version]

    def initialize(quote_version:, reason:)
      @quote_version = quote_version
      @reason = reason
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote_version") unless quote_version
      return result.forbidden_failure! unless quote_version.organization.feature_flag_enabled?(:order_forms)
      return result.validation_failure!(errors: {quote_version: ["invalid_void_reason"]}) unless valid_reason?(reason:)
      return result.not_allowed_failure!(code: "inappropriate_state") unless voidable?

      quote_version.update!(
        status: :voided,
        void_reason: reason,
        voided_at: Time.current,
        share_token: nil,
        approved_at: nil
      )

      # TODO: SendWebhookJob.perform_after_commit("quote_version.voided", quote_version)

      result.quote_version = quote_version
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::ActiveRecordError => e
      result.service_failure!(code: "void_failed", message: e.message, error: e)
    end

    private

    def voidable?
      quote_version.approved? || quote_version.draft?
    end

    def valid_reason?(reason:)
      return false if reason.blank?

      QuoteVersion::VOID_REASONS.has_key?(reason.to_s.to_sym)
    end
  end
end
