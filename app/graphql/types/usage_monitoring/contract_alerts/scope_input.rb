# frozen_string_literal: true

module Types
  module UsageMonitoring
    module ContractAlerts
      class ScopeInput < BaseInputObject
        graphql_name "ContractAlertScopeInput"

        argument :product_code, String, required: true
        argument :product_filter_codes, [String], required: false
        argument :type, ScopeTypeEnum, required: true
        argument :with_product_filters, Boolean, required: false
      end
    end
  end
end
