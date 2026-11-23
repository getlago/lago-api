# frozen_string_literal: true

module Types
  module UsageMonitoring
    module ContractAlerts
      class UpdateInput < BaseInputObject
        argument :id, ID, required: true

        argument :name, String, required: false

        argument :thresholds, [Types::UsageMonitoring::Alerts::ThresholdInput], required: false
      end
    end
  end
end
