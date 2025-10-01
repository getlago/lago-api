# frozen_string_literal: true

module Charges
  class SyncChildrenBatchService < BaseService
    Result = BaseResult
    def initialize(children_plans_ids:, charge:)
      @children_plans_ids = children_plans_ids
      @charge = charge
      super
    end

    def call
      return result.not_found_failure!(resource: "charge") unless charge
      return result.not_found_failure!(resource: "plan") unless charge.plan

      charge.plan.children.where(id: children_plans_ids).each do |child_plan|
        create_child_charge_if_needed(child_plan, charge)
      end
      result
    end

    private

    attr_reader :child_ids, :charge

    def create_child_charge_if_needed(child_plan, charge)
      return if child_plan.charges.where(parent_id: charge.id).exists?
      # if there is only one possible child charge and it has a parent_id and parent is deleted, we can update it
      possible_child_charges = child_plan.charges.where(billable_metric_id: charge.billable_metric_id, charge_model: charge.charge_model)
      if possible_child_charges.count == 1 && possible_child_charges.first.parent_id.present? && possible_child_charges.first.parent.nil?
        possible_child_charges.first.update(parent_id: charge.id)
        return
      end
     
      filters_params = charge.filters.map do |filter|
        {
          invoice_display_name: filter.invoice_display_name,
          properties: filter.properties,
          values: filter.to_h
        }
     end
     params = charge.attributes.symbolize_keys.compact.merge(parent_id: charge.id, filters: filters_params)

      Charges::CreateService.call!(plan: child_plan, params: params)
    end
  end
end
