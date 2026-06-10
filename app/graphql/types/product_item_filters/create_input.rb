# frozen_string_literal: true

module Types
  module ProductItemFilters
    class CreateInput < BaseInputObject
      description "Create product item filter input arguments"

      argument :code, String, required: true
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: true
      argument :product_item_id, ID, required: true
      argument :values, [Types::ProductItemFilterValues::Input], required: true
    end
  end
end
