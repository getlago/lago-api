# frozen_string_literal: true

module Types
  module CatalogPlans
    class CreateInput < BaseInputObject
      graphql_name "CreateCatalogPlanInput"
      description "Create catalog plan input arguments"

      argument :code, String, required: true
      argument :currency, Types::CurrencyEnum, required: true
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: true
    end
  end
end
