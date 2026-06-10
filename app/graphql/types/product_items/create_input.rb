# frozen_string_literal: true

module Types
  module ProductItems
    class CreateInput < BaseInputObject
      description "Create product item input arguments"

      argument :billable_metric_id, ID, required: false
      argument :code, String, required: true
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :item_type, Types::ProductItems::ItemTypeEnum, required: true
      argument :name, String, required: true
      argument :product_id, ID, required: false
    end
  end
end
