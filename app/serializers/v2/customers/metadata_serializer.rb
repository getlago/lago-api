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
          created_at: format_time(model.created_at),
          updated_at: format_time(model.updated_at)
        }
      end
    end
  end
end
