# frozen_string_literal: true

module Types
  module Products
    class CreateInput < BaseInputObject
      description "Create product input arguments"

      argument :billable_metric_id, ID, required: false
      argument :code, String, required: true
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: true
      argument :product_category_id, ID, required: false
      argument :product_type, Types::Products::ProductTypeEnum, required: true
    end
  end
end
