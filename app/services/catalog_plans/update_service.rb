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
      action: "plan.updated",
      record: -> { catalog_plan }
    )

    def call
      return result.not_found_failure!(resource: "plan") unless catalog_plan

      # A contract prices against the plan by reference — it serializes the
      # plan_code through the association (so the code must stay stable) and its
      # fees invoice in the plan currency. Once a contract is attached both are
      # frozen; name, description and invoice display name stay editable.
      if catalog_plan.attached_to_contracts? && (code_change_requested? || currency_change_requested?)
        return result.single_validation_failure!(field: :plan, error_code: "plan_locked")
      end

      # Plan-level rate cards freeze the currency too, before any contract: the
      # cards were validated against it and changing it would desync them.
      if currency_change_requested? && catalog_plan.applied_rate_cards.exists?
        return result.single_validation_failure!(field: :currency, error_code: "not_editable_with_applied_rate_cards")
      end

      catalog_plan.name = params[:name] if params.key?(:name)
      catalog_plan.code = params[:code] if params.key?(:code)
      catalog_plan.description = params[:description] if params.key?(:description)
      catalog_plan.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      catalog_plan.currency = params[:currency] if params.key?(:currency)
      catalog_plan.save!

      result.catalog_plan = catalog_plan
      SendWebhookJob.perform_after_commit("plan.updated", catalog_plan) if send_webhook
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :catalog_plan, :params, :send_webhook

    def code_change_requested?
      params.key?(:code) && params[:code] != catalog_plan.code
    end

    def currency_change_requested?
      params.key?(:currency) && params[:currency] != catalog_plan.currency
    end
  end
end
