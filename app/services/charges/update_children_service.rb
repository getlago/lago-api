# frozen_string_literal: true

module Charges
  class UpdateChildrenService < BaseService
    Result = BaseResult[:charge]

    def initialize(charge:, params:, old_parent_attrs:, old_parent_filters_attrs:, old_parent_applied_pricing_unit_attrs:, child_ids:)
      @charge = charge
      @params = params
      @parent_filters = old_parent_filters_attrs
      @old_parent = Charge.new(old_parent_attrs)
      @child_ids = child_ids

      if old_parent_applied_pricing_unit_attrs.present?
        @old_parent.build_applied_pricing_unit(old_parent_applied_pricing_unit_attrs)
      end

      super
    end

    def call
      return result unless charge

      ActiveRecord::Base.transaction do
        charge.children.where(id: child_ids).find_each do |child_charge|
          Charges::UpdateService.call!(
            charge: child_charge,
            params:,
            cascade_options: {
              cascade: true,
              parent_filters:,
              equal_properties: old_parent.equal_properties?(child_charge),
              equal_applied_pricing_unit_rate: old_parent.equal_applied_pricing_unit_rate?(child_charge)
            }
          )
        end
      end

      result.charge = charge
      result
    end

    private

    attr_reader :charge, :params, :old_parent, :parent_filters, :child_ids
  end
end
