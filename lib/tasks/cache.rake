# frozen_string_literal: true

namespace :cache do
  desc 'Reset the current usage cache for migration from group to filters'
  task remove_group_usage_cache: :environment do
    charge_id = Charge.joins(:group_properties).select(:id)

    Charge.where(id: charge_id).includes(plan: :subscriptions).find_each do |charge|
      charge.plan.subscriptions.find_each do |subscription|
        Subscriptions::ChargeCacheService.new(subscription:, charge:).expire_cache
      end
    end
  end
end
