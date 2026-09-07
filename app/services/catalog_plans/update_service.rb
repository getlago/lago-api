# frozen_string_literal: true

module CatalogPlans
  class UpdateService < BaseService
    Result = BaseResult[:catalog_plan]

    def initialize(catalog_plan:, params:, send_webhook: true)
      @catalog_plan = catalog_plan
      @params = params
      @send_webhook = send_webhook
      super()
    end

    activity_loggable(
      action: "catalog_plan.updated",
      record: -> { catalog_plan }
    )

    def call
      return result.not_found_failure!(resource: "plan") unless catalog_plan

      catalog_plan.name = params[:name] if params.key?(:name)
      catalog_plan.code = params[:code] if params.key?(:code)
      catalog_plan.description = params[:description] if params.key?(:description)
      catalog_plan.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      catalog_plan.currency = params[:currency] if params.key?(:currency)
      catalog_plan.save!

      result.catalog_plan = catalog_plan
      SendWebhookJob.perform_after_commit("catalog_plan.updated", catalog_plan) if send_webhook
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :catalog_plan, :params, :send_webhook
  end
end
