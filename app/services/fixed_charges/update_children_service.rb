# frozen_string_literal: true

module FixedCharges
  class UpdateChildrenService < BaseService
    Result = BaseResult[:fixed_charge]

    def initialize(fixed_charge:, params:, old_parent_attrs:, child_ids:, timestamp:)
      @fixed_charge = fixed_charge
      @params = params.deep_symbolize_keys
      @old_parent = FixedCharge.new(old_parent_attrs)
      @child_ids = child_ids
      @timestamp = timestamp

      super
    end

    def call
      return result unless fixed_charge

      ActiveRecord::Base.transaction do
        # skip touching to avoid deadlocks
        Plan.no_touching do
          fixed_charge.children.where(id: child_ids).find_each do |child_fixed_charge|
            FixedCharges::UpdateService.call!(
              fixed_charge: child_fixed_charge,
              params:,
              timestamp:,
              cascade_options: {
                cascade: true,
                equal_properties: old_parent.equal_properties?(child_fixed_charge)
              }
            )

            # Trigger billing for child fixed charge if pay_in_advance and apply_units_immediately
            trigger_pay_in_advance_billing(child_fixed_charge) if should_trigger_billing?(child_fixed_charge)
          end
        end
      end

      result.fixed_charge = fixed_charge
      result
    end

    private

    attr_reader :fixed_charge, :params, :old_parent, :child_ids, :timestamp

    def should_trigger_billing?(child_fixed_charge)
      params[:apply_units_immediately] && child_fixed_charge.pay_in_advance?
    end

    def trigger_pay_in_advance_billing(child_fixed_charge)
      child_fixed_charge.plan.subscriptions.active.find_each do |subscription|
        Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(
          subscription,
          timestamp
        )
      end
    end
  end
end
