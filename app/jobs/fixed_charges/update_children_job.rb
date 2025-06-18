# frozen_string_literal: true

module FixedCharges
  class UpdateChildrenJob < ApplicationJob
    queue_as :default

    def perform(params:, old_parent_attrs:, old_parent_filters_attrs:, old_parent_applied_pricing_unit_attrs:, fixed_charges_affect_immediately:)
      fixed_charge = FixedCharge.find_by(id: old_parent_attrs["id"])

      FixedCharges::UpdateChildrenService.call!(
        fixed_charge:,
        params:,
        old_parent_attrs:,
        old_parent_properties_attrs:,
        fixed_charges_affect_immediately:
      )
    end
  end
end
