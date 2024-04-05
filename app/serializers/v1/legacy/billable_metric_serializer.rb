# frozen_string_literal: true

module V1
  module Legacy
    class BillableMetricSerializer < ModelSerializer
      def serialize
        {
          group: model.active_groups_as_tree,
        }
      end
    end
  end
end
