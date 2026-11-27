# frozen_string_literal: true

module Types
  module UsageMonitoring
    module ContractAlerts
      class ScopeObject < Types::BaseObject
        graphql_name "ContractAlertScope"

        field :product, Types::Products::Object, null: false
        field :product_filters, [Types::ProductFilters::Object]
        field :type, ScopeTypeEnum, null: false
        field :with_product_filters, Boolean
      end
    end
  end
end
