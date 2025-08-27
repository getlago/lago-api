# frozen_string_literal: true

module V1
  class SubscriptionFixedChargeUnitsOverrideSerializer < ModelSerializer
    def serialize
      {
        id: model.id,
        fixed_charge_id: model.fixed_charge_id,
        add_on_id: model.fixed_charge.add_on_id,
        units: model.units
      }
    end
  end
end
