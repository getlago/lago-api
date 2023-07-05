# frozen_string_literal: true

module V1
  module Plans
    class AppliedTaxSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_plan_id: model.plan.id,
          lago_tax_id: model.tax.id,
          tax_code: model.tax.code,
          plan_code: model.plan.code,
          created_at: model.created_at.iso8601,
        }
      end
    end
  end
end
