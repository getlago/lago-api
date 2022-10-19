# frozen_string_literal: true

module Types
  module Charges
    class Input < Types::BaseInputObject
      graphql_name 'ChargeInput'

      argument :id, ID, required: false
      argument :billable_metric_id, ID, required: true
      argument :charge_model, Types::Charges::ChargeModelEnum, required: true

      argument :properties, Types::Charges::PropertiesInput, required: false
      argument :group_properties, [Types::Charges::GroupPropertiesInput], required: false
    end
  end
end
