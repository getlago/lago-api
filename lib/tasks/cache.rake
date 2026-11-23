# frozen_string_literal: true

namespace :cache do
  desc "Expire cache for a given subscription"
  task expire_subscription_cache: :environment do
    subscription = Subscription.find(ENV["subscription_id"])
    puts "Expiring cache for subscription #{subscription.id}"

    Subscriptions::ChargeCacheService.expire_for_subscription(subscription)
  end
end
