# frozen_string_literal: true

module Charges
  class UpdateChildrenService < BaseService
    Result = BaseResult[:charge]

    def initialize(charge:, params:)
      @charge = charge
      @params = params
      super
    end

    def call
      return result unless charge

      ActiveRecord::Base.transaction do
        charge.children.find_each do |child_charge|
          Charges::UpdateService.call!(
            charge: child_charge,
            params:,
            cascade_options:{
              cascade: true,
              parent_filters: charge.filters.map(&:attributes),
              equal_properties: charge.equal_properties?(child_charge)
            }
          )
        end
      end

      result.charge = charge
      result
    end

    private

    attr_reader :charge, :params
  end
end
