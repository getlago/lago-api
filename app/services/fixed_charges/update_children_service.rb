# frozen_string_literal: true

module FixedCharges
  class UpdateChildrenService < BaseService
    Result = BaseResult[:fixed_charge]

    def initialize(fixed_charge:, params:, old_parent_attrs:, old_parent_properties_attrs:, fixed_charges_affect_immediately:)
      @fixed_charge = fixed_charge
      @params = params
      @old_parent = FixedCharge.new(old_parent_attrs)
      @fixed_charges_affect_immediately = fixed_charges_affect_immediately

      super
    end

    def call
      return result unless fixed_charge

      ActiveRecord::Base.transaction do
        fixed_charge.children.find_each do |child_fixed_charge|
          FixedCharges::UpdateService.call!(
            fixed_charge: child_fixed_charge,
            params:,
            cascade_options: {
              cascade: true,
              equal_properties: old_parent.equal_properties?(child_fixed_charge)
            },
            fixed_charges_affect_immediately:
          )
        end
      end

      result.fixed_charge = fixed_charge
      result
    end

    private

    attr_reader :fixed_charge, :params, :old_parent, :fixed_charges_affect_immediately
  end
end
