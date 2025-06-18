# frozen_string_literal: true

module FixedCharges
  class CreateChildrenService < BaseService
    Result = BaseResult[:fixed_charge]

    def initialize(fixed_charge:, payload:)
      @fixed_charge = fixed_charge
      @payload = payload.deep_symbolize_keys
      super
    end

    def call
      return result.not_found_failure!(resource: "fixed_charge") unless fixed_charge

      ActiveRecord::Base.transaction do
        plan.children.find_each do |child|
          FixedCharges::CreateService.call!(plan: child, params: payload.merge(parent_id: fixed_charge.id))
        end
      end

      result.fixed_charge = fixed_charge
      result
    end

    private

    attr_reader :fixed_charge, :payload

    delegate :plan, to: :fixed_charge
  end
end
