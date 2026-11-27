# frozen_string_literal: true

module Types
  module UsageMonitoring
    module ContractAlerts
      class CreateInput < BaseInputObject
        argument :alert_type, Types::UsageMonitoring::ContractAlerts::AlertTypeEnum, required: true
        argument :contract_id, ID, required: true

        argument :code, String, required: true
        argument :name, String, required: false
        argument :scope, [Types::UsageMonitoring::ContractAlerts::ScopeInput], required: true

        argument :thresholds, [Types::UsageMonitoring::Alerts::ThresholdInput], required: true
      end
    end
  end
end
