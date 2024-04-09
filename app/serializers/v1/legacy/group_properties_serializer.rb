# frozen_string_literal: true

module V1
  module Legacy
    class GroupPropertiesSerializer < ModelSerializer
      def serialize
        {
          group_id: model.group_id,
          values: model.values,
          invoice_display_name: model.invoice_display_name,
        }
      end
    end
  end
end
