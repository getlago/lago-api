# frozen_string_literal: true

module UsageChargeGroups
  class CreateService < BaseService
    def initialize(subscription:)
      super
      @subscription = subscription
    end

    def call
      create_usage_charge_group if has_group_charge?
    end

    private

    attr_reader :subscription

    delegate :plan, to: :subscription

    def has_group_charge?
      subscription.plan.charge_groups.present?
    end

    def create_usage_charge_group
      plan.charge_groups.each do |charge_group|
        usage_charge_group = UsageChargeGroup.new(
          charge_group_id: charge_group.id,
          subscription_id: subscription.id,
          current_package_count: 1,
        )
        usage_charge_group.save!
      end
    end
  end
end
