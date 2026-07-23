# frozen_string_literal: true

module Types
  module ProductItemFilters
    class UpdateInput < BaseInputObject
      description "Update product item filter input arguments"

      argument :id, ID, required: true

      argument :code, String, required: false
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: false
      argument :values, [Types::ProductItemFilterValues::Input], required: false
    end
  end
end
