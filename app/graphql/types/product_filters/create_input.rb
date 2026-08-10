# frozen_string_literal: true

module Types
  module ProductFilters
    class CreateInput < BaseInputObject
      description "Create product filter input arguments"

      argument :code, String, required: true
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: true
      argument :product_id, ID, required: true
      argument :values, [Types::ProductFilterValues::Input], required: true
    end
  end
end
