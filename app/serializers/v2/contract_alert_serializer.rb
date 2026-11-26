# frozen_string_literal: true

module V2
  class ContractAlertSerializer < ModelSerializer
    timestamps :last_processed_at, :created_at, :updated_at, :deleted_at

    def serialize
      {
        lago_id: model.id,
        external_contract_id: model.contract_external_id,
        code: model.code,
        name: model.name,
        alert_type: model.alert_type,
        applies_to: {type: "contract"},
        product_code: model.product&.code,
        product_filter_code: model.product_filter&.code,
        with_product_filters: model.with_product_filters,
        direction: model.direction,
        thresholds:,
        previous_value: model.previous_value
      }
    end

    private

    def thresholds
      model.thresholds
        .sort_by { [it.recurring ? 1 : 0, it.value] }
        .map { ::V2::AlertThresholdSerializer.new(it, nested_options).serialize }
    end
  end
end
