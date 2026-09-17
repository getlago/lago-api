# frozen_string_literal: true

module Types
  module RatePhases
    class Object < Types::BaseObject
      graphql_name "RatePhase"
      description "A phase in the ordered rate schedule of a plan product"

      dataload_association :rate_override

      field :billing_interval_cycle_count, Integer, null: true
      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: true
      field :position, Integer, null: false
      field :rate_override, Types::RateOverrides::Object, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
