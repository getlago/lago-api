# frozen_string_literal: true

module FixedCharges
  class DestroyChildrenService < BaseService
    Result = BaseResult[:fixed_charge]

    def initialize(fixed_charge)
      @fixed_charge = fixed_charge
      super
    end

    def call
      return result unless fixed_charge
      return result unless fixed_charge.discarded?

      ActiveRecord::Base.transaction do
        fixed_charge.children.find_each { FixedCharges::DestroyService.call!(fixed_charge: it) }
      end

      result.fixed_charge = fixed_charge
      result
    end

    private

    attr_reader :fixed_charge
  end
end
