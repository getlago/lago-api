# frozen_string_literal: true

module Types
  module TaxRates
    class UpdateInput < Types::BaseInputObject
      graphql_name 'TaxRateUpdateInput'

      argument :code, String, required: false
      argument :description, String, required: false
      argument :id, ID, required: true
      argument :name, String, required: false
      argument :value, Float, required: false
    end
  end
end
