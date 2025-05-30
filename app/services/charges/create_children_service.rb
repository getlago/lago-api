# frozen_string_literal: true

module Charges
  class CreateChildrenService < BaseService
    Result = BaseResult[:charge]

    def initialize(charge:, payload:)
      @charge = charge
      @payload = payload.deep_symbolize_keys
      super
    end

    def call
      return result.not_found_failure!(resource: "charge") unless charge

      ActiveRecord::Base.transaction do
        plan.children.find_each do |child|
          Charges::CreateService.call!(plan: child, params: payload.merge(parent_id: charge.id))
        end
      end

      result.charge = charge
      result
    end

    private

    attr_reader :charge, :payload

    delegate :plan, to: :charge
  end
end
