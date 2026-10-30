# frozen_string_literal: true

module V2
  module Customers
    class MetadataSerializer < ModelSerializer
      timestamps :created_at, :updated_at

      def serialize
        {
          lago_id: model.id,
          key: model.key,
          value: model.value,
          display_on_invoice: model.display_in_invoice
        }
      end
    end
  end
end
