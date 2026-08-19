# frozen_string_literal: true

module QuoteVersions
  class VoidService < BaseService
    include OrderForms::Premium

    attr_reader :quote_version, :reason

    Result = BaseResult[:quote_version]

    def initialize(quote_version:, reason:)
      @quote_version = quote_version
      @reason = reason
      super
    end

    def call
      return result.not_found_failure!(resource: "quote_version") unless quote_version
      return result.forbidden_failure! unless order_forms_enabled?(quote_version.organization)
      return result.single_validation_failure!(field: :void_reason, error_code: "invalid") unless valid_reason?

      QuoteVersion.transaction do
        Quotes::LockService.call(quote: quote_version.quote) do
          quote_version.reload
          next result.single_validation_failure!(field: :status, error_code: "not_voidable") unless voidable?

          quote_version.update!(
            status: :voided,
            void_reason: reason,
            voided_at: Time.current,
            approved_at: nil
          )

          SendWebhookJob.perform_after_commit("quote.voided", quote_version)
          Utils::ActivityLog.produce_after_commit(quote_version, "quote.voided")

          result.quote_version = quote_version
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseLockService::FailedToAcquireLock
      result.single_validation_failure!(field: :base, error_code: "concurrency_conflict")
    end

    private

    def voidable?
      return true if quote_version.draft?

      quote_version.approved? && cascade_reason?
    end

    def cascade_reason?
      QuoteVersion::CASCADE_VOID_REASONS.key?(reason.to_sym)
    end

    def valid_reason?
      return false if reason.blank?

      QuoteVersion::VOID_REASONS.has_key?(reason.to_s.to_sym)
    end
  end
end
