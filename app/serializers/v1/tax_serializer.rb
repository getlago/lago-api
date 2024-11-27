# frozen_string_literal: true

module V1
  class TaxSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        rate: model.rate,
        description: model.description,
        applied_to_organization: model.applied_to_organization,
        add_ons_count: model.add_ons.count,
        customers_count: model.customers_count,
        plans_count: model.plans.count,
        charges_count:,
        commitments_count: model.commitments.count,
        created_at: model.created_at.iso8601
      }
    end

    private

    def charges_count
      Charges::AppliedTax.where(tax_id: model.id).count('charge_id')
    end
  end
end
