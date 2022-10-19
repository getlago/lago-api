# frozen_string_literal: true

module Types
  module Charges
    class Object < Types::BaseObject
      graphql_name 'Charge'

      field :id, ID, null: false
      field :billable_metric, Types::BillableMetrics::Object, null: false
      field :charge_model, Types::Charges::ChargeModelEnum, null: false
      field :properties, Types::Charges::Properties, null: true
      field :group_properties, [Types::Charges::GroupProperties], null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
