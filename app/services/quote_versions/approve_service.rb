# frozen_string_literal: true

module QuoteVersions
  class ApproveService < BaseService
    attr_reader :quote_version

    Result = BaseResult[:quote_version]

    def initialize(quote_version:)
      @quote_version = quote_version
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote_version") unless quote_version
      return result.forbidden_failure! unless quote_version.organization.feature_flag_enabled?(:order_forms)
      return result.not_allowed_failure!(code: "inappropriate_state") unless approvable?
      validation_errors = validate
      return result.validation_failure!(errors: {quote_version: validation_errors}) if validation_errors.any?

      quote_version.update!(
        status: :approved,
        approved_at: Time.current
      )

      # TODO: OrderForms::CreateService.call
      # TODO: SendWebhookJob.perform_after_commit("quote_version.approved", quote_version)

      result.quote_version = quote_version
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::ActiveRecordError => e
      result.service_failure!(code: "approval_failed", message: e.message, error: e)
    end

    private

    def approvable?
      quote_version.draft?
    end

    def validate
      []
      # TODO: payload checks
    end
  end
end
