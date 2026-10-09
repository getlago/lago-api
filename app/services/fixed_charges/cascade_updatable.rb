# frozen_string_literal: true

module FixedCharges
  module CascadeUpdatable
    extend ActiveSupport::Concern

    private

    def trigger_cascade(old_parent_attrs:)
      return unless cascade_updates
      return unless fixed_charge.children.exists?

      if fixed_charge.cascaded_attributes_changed?(old_parent_attrs)
        FixedCharges::UpdateChildrenJob.perform_later(
          params: build_cascade_params.deep_stringify_keys,
          old_parent_attrs:
        )
      end
    end

    def build_cascade_params
      {
        code: fixed_charge.code,
        charge_model: fixed_charge.charge_model,
        properties: fixed_charge.properties,
        units: fixed_charge.units
      }
    end
  end
end
