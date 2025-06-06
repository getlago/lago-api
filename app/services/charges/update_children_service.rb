# frozen_string_literal: true

module Charges
  class UpdateChildrenService < BaseService
    Result = BaseResult[:charge]

    def initialize(charge:, params:, old_parent_attrs:, old_parent_filters_attrs:)
      @charge = charge
      @params = params
      @old_parent = Charge.new(old_parent_attrs)
      @parent_filters = old_parent_filters_attrs
      super
    end

    def call
      return result unless charge

      ActiveRecord::Base.transaction do
        charge.children.find_each do |child_charge|
          Charges::UpdateService.call!(
            charge: child_charge,
            params:,
            cascade_options: {
              cascade: true,
              parent_filters:,
              equal_properties: old_parent.equal_properties?(child_charge)
            }
          )
        end
      end

      result.charge = charge
      result
    end

    private

    attr_reader :charge, :params, :old_parent, :parent_filters
  end
end
