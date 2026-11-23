# frozen_string_literal: true

module Types
  module UsageMonitoring
    module ContractAlerts
      class AlertTypeEnum < Types::BaseEnum
        graphql_name "ContractAlertTypeEnum"

        ::UsageMonitoring::ContractAlert::STI_MAPPING.each_key do |type|
          value type
        end
      end
    end
  end
end
