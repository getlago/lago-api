# frozen_string_literal: true

module Types
  module ChargeFilters
    class Object < Types::BaseObject
      graphql_name 'ChargeFilter'
      description 'Charge filters object'

      field :id, ID, null: false

      field :invoice_display_name, String, null: true
      field :properties, Types::Charges::Properties, null: false
      field :values, Types::ChargeFilters::Values, null: false

      def values
        object.values.each_with_object({}) do |filter_value, result|
          result[filter_value.billable_metric_filter.key] = filter_value.value
        end
      end
    end
  end
end
