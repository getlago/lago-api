# frozen_string_literal: true

module Types
  module CatalogPlans
    class UpdateInput < BaseInputObject
      graphql_name "UpdateCatalogPlanInput"
      description "Update catalog plan input arguments"

      argument :id, ID, required: true

      argument :code, String, required: false
      argument :currency, Types::CurrencyEnum, required: false
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: false
    end
  end
end
