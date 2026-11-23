# frozen_string_literal: true

module V2
  # A wallet alert. On a plan wallet's template, the contract fields and the evaluation state are
  # null, so templates and contract wallet alerts render one shape.
  class CatalogWalletAlertSerializer < ModelSerializer
    timestamps :last_processed_at, :created_at, :updated_at

    def serialize
      {
        lago_id: model.id,
        lago_wallet_id: model.plan_wallet_id,
        wallet_code: model.plan_wallet.code,
        currency: model.plan_wallet.currency,
        plan_code: model.plan_wallet.catalog_plan.code,
        external_contract_id: nil,
        external_customer_id: nil,
        code: model.code,
        name: model.name,
        alert_type: model.alert_type,
        direction: model.decreasing? ? "decreasing" : "increasing",
        thresholds:,
        previous_value: nil
      }
    end

    private

    # By value with the recurring one last, as contract usage alerts render them. Sorted in memory so
    # that a list reads its preloaded thresholds.
    def thresholds
      model.thresholds
        .sort_by { [it.recurring ? 1 : 0, it.value] }
        .map { ::V2::AlertThresholdSerializer.new(it, nested_options).serialize }
    end

    # A template is never evaluated.
    def last_processed_at = nil
  end
end
