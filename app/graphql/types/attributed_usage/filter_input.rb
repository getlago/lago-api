# frozen_string_literal: true

module Types
  module AttributedUsage
    class FilterInput < Types::BaseInputObject
      graphql_name "AttributedUsageFilterInput"
      description "Keeps the events whose attribution label of the given type matches one of the values. An empty value matches the events without that label."

      argument :code, String, required: true, description: "Code of the usage attribution type"
      argument :values, [String], required: true
    end
  end
end
