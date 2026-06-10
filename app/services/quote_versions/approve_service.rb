# frozen_string_literal: true

module QuoteVersions
  class ApproveService < BaseService
    include OrderForms::Premium

    attr_reader :quote_version

    Result = BaseResult[:quote_version, :order_form]

    def initialize(quote_version:)
      @quote_version = quote_version
      super
    end

    def call
      return result.not_found_failure!(resource: "quote_version") unless quote_version
      return result.forbidden_failure! unless order_forms_enabled?(quote_version.organization)
      return result.not_allowed_failure!(code: "inappropriate_state") unless approvable?

      QuoteVersion.transaction do
        quote_version.update!(
          status: :approved,
          approved_at: Time.current
        )

        result.order_form = OrderForms::CreateService.call!(quote_version:).order_form
      end

      # TODO: SendWebhookJob.perform_after_commit("quote_version.approved", quote_version)

      result.quote_version = quote_version
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def approvable?
      quote_version.draft?
    end
  end
end
