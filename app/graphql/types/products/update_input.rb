# frozen_string_literal: true

module Types
  module Products
    class UpdateInput < BaseInputObject
      description "Update product input arguments"

      argument :id, ID, required: true

      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: false
    end
  end
end
