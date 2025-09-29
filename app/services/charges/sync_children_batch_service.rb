# frozen_string_literal: true

module Charges
  class SyncChildrenBatchService < BaseService
    Result = BaseResult
    def initialize(child_ids:, charge:)
      @child_ids = child_ids
      @charge = charge
      super
    end

    def call
      return result.not_found_failure!(resource: "charge") unless charge
      return result.not_found_failure!(resource: "plan") unless charge.plan

      charge.plan.children.where(id: child_ids).each do |child_plan|
        create_child_charge_if_needed(child_plan, charge)
      end
      result
    end

    private

    attr_reader :child_ids, :charge

    def create_child_charge_if_needed(child_plan, charge)
      return if child_plan.charges.where(parent_id: charge.id).exists?

      Charges::CreateService.call!(plan: child_plan, params: charge.attributes.symbolize_keys.compact.merge(parent_id: charge.id))
    end
  end
end