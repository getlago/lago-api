# frozen_string_literal: true

module UsageChargeGroups
  class CreateService < BaseService
    def initialize(subscription:)
      super
      @subscription = subscription
    end

    def call
      is_group_charge?
      create_usage_charge_group
    end

    private

    attr_reader :subscription

    delegate :plan, to: :subscription

    def is_group_charge?
      subscription.plan.charge_groups.present?
    end

    def create_usage_charge_group
      plan.charge_groups.each do |charge_group|
        usage_charge_group = UsageChargeGroup.new(
          charge_group_id: charge_group.id,
          subscription_id: subscription.id,
          current_package_count: 1,
        )
        usage_charge_group.available_group_usage = compute_available_group_usage(charge_group)
        usage_charge_group.save!
      end
    end

    def compute_available_group_usage(charge_group)
      available_group_usage = {}
      charge_group.charges.package_group.each do |charge|
        billable_metric = charge.billable_metric
        available_group_usage[billable_metric.id] = charge.properties['package_size']
      end

      available_group_usage
    end
  end
end
