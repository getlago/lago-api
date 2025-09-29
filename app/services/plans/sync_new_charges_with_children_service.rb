# frozen_string_literal: true

module Plans
  class SyncNewChargesWithChildrenService < BaseService
    def initialize(plan:)
      @plan = plan
      super
    end

    def call
      plan.charges.each do |charge|
        sync_charge_for_children(charge)
      end
    end

    private

    attr_reader :plan

    def sync_charge_for_children(charge)
      plan.children.joins(:subscriptions).where(subscriptions: {status: %w[active pending]}).distinct.pluck(:id).each_slice(20) do |child_ids|
        Charges::SyncChildrenBatchJob.perform_later(
          child_ids:,
          charge:
        )
      end
    end
  end
end
