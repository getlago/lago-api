# frozen_string_literal: true

module Types
  module TaxRates
    class CreateInput < Types::BaseInputObject
      graphql_name 'TaxRateCreateInput'

      argument :code, String, required: true
      argument :description, String, required: false
      argument :name, String, required: true
      argument :value, Float, required: true
    end
  end
end
