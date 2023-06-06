# frozen_string_literal: true

module Types
  module BillableMetrics
    class UpdateInput < BaseInputObject
      description 'Update Billable metric input arguments'

      argument :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, required: true
      argument :code, String, required: true
      argument :description, String
      argument :field_name, String, required: false
      argument :group, GraphQL::Types::JSON, required: false
      argument :id, String, required: true
      argument :name, String, required: true
      argument :recurring, Boolean, required: false
    end
  end
end
