# frozen_string_literal: true

module V2
  # A wallet alert. A plan wallet's template names its plan, while a contract wallet's alert names its contract and
  # customer and carries its evaluation state, so templates and contract wallet alerts render one shape.
  class CatalogWalletAlertSerializer < ModelSerializer
    timestamps :last_processed_at, :created_at, :updated_at

    def serialize
      {
        lago_id: model.id,
        lago_wallet_id: wallet.id,
        wallet_code: wallet.code,
        currency: wallet.currency,
        plan_code: template? ? wallet.catalog_plan.code : nil,
        lago_contract_id: template? ? nil : wallet.contract_id,
        external_contract_id: template? ? nil : wallet.contract.external_id,
        contract_code: template? ? nil : wallet.contract.code,
        external_customer_id: template? ? nil : wallet.customer.external_id,
        code: model.code,
        name: model.name,
        alert_type: model.alert_type,
        direction: model.decreasing? ? "decreasing" : "increasing",
        thresholds:,
        previous_value: template? ? nil : model.previous_value
      }
    end

    private

    def template? = model.is_a?(::UsageMonitoring::PlanWalletAlert)

    def wallet = template? ? model.plan_wallet : model.catalog_wallet

    # By value with the recurring one last, as contract usage alerts render them. Sorted in memory so
    # that a list reads its preloaded thresholds.
    def thresholds
      model.thresholds
        .sort_by { [it.recurring ? 1 : 0, it.value] }
        .map { ::V2::AlertThresholdSerializer.new(it, nested_options).serialize }
    end

    # A template is never evaluated.
    def last_processed_at = template? ? nil : model.last_processed_at
  end
end
