# frozen_string_literal: true

module Types
  module ProductCategories
    class CreateInput < BaseInputObject
      description "Create product_category input arguments"

      argument :code, String, required: true
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: true
    end
  end
end
