# frozen_string_literal: true

module Fees
  # Finds the charge, and the filter, whose price a fee would use today: the fee's own charge
  # when it is still on the subscription's plan, or the first-override child charge
  # (parent_id = the fee's charge). Filters of a child charge are matched by code.
  # Both values are nil when the charge or filter is discarded or has no current match,
  # so callers keep the historical values of the fee.
  class ResolveCurrentChargeService < BaseService
    Result = BaseResult[:charge, :charge_filter]

    def initialize(subscription:, charge:, charge_filter: nil)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter

      super
    end

    def call
      return result unless resolvable?

      current_charge = plan_charges.find_by(id: charge.id) || plan_charges.find_by(parent_id: charge.id)
      return result unless current_charge

      current_filter = resolve_filter(current_charge)
      return result if charge_filter && current_filter.nil?

      result.charge = current_charge
      result.charge_filter = current_filter
      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter

    def resolvable?
      return false if subscription.nil? || charge.nil? || charge.discarded?

      charge_filter.nil? || charge_filter.kept?
    end

    def plan_charges
      @plan_charges ||= subscription.plan.charges
    end

    def resolve_filter(current_charge)
      return if charge_filter.nil?
      return charge_filter if current_charge.id == charge.id
      return if charge_filter.code.blank?

      current_charge.filters.find_by(code: charge_filter.code)
    end
  end
end
