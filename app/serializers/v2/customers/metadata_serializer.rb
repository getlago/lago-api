# frozen_string_literal: true

module V2
  module Customers
    class MetadataSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          key: model.key,
          value: model.value,
          display_on_invoice: model.display_in_invoice,
          created_at: model.created_at.iso8601,
          updated_at: model.updated_at.iso8601
        }
      end
    end
  end
end
