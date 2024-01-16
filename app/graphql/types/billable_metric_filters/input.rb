# frozen_string_literal: true

module Types
  module BillableMetricFilters
    class Input < BaseInputObject
      description 'Billable metric filters input arguments'

      argument :key, String, required: true
      argument :values, [String], required: true
    end
  end
end
