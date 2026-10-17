# frozen_string_literal: true

module CatalogPlans
  class CreateService < BaseService
    Result = BaseResult[:catalog_plan]

    def initialize(args, send_webhook: true)
      @args = args
      @send_webhook = send_webhook
      super()
    end

    activity_loggable(
      action: "plan.created",
      record: -> { result.catalog_plan }
    )

    def call
      ActiveRecord::Base.transaction do
        catalog_plan = CatalogPlan.create!(
          organization_id: args[:organization_id],
          name: args[:name],
          code: args[:code],
          description: args[:description],
          invoice_display_name: args[:invoice_display_name],
          currency: args[:currency]
        )

        apply_taxes(catalog_plan)

        result.catalog_plan = catalog_plan
      end

      SendWebhookJob.perform_after_commit("plan.created", result.catalog_plan) if send_webhook
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :args, :send_webhook

    def apply_taxes(catalog_plan)
      return unless args.key?(:tax_codes) && !args[:tax_codes].nil?

      CatalogPlans::ApplyTaxesService.call!(catalog_plan:, tax_codes: args[:tax_codes])
    end
  end
end
