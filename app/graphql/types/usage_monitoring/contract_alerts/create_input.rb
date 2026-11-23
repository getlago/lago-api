# frozen_string_literal: true

module Types
  module UsageMonitoring
    module ContractAlerts
      class CreateInput < BaseInputObject
        argument :alert_type, Types::UsageMonitoring::ContractAlerts::AlertTypeEnum, required: true
        argument :contract_id, ID, required: true

        argument :code, String, required: true
        argument :name, String, required: false
        argument :product_filter_id, ID, required: false
        argument :product_id, ID, required: false

        argument :thresholds, [Types::UsageMonitoring::Alerts::ThresholdInput], required: true
      end
    end
  end
end
