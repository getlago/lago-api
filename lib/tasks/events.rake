# frozen_string_literal: true

namespace :events do
  # NOTE: related to https://github.com/getlago/lago-api/issues/317
  desc 'Fill missing timestamps for events'
  task fill_timestamp: :environment do
    Event.where(timestamp: nil).find_each do |event|
      event.update!(timestamp: event.created_at)
    end
  end

  desc 'Fill missing subscription_id'
  task fill_subscription: :environment do
    Event.where(subscription_id: nil).find_each do |event|
      subscription = event.customer.active_subscription || event.customer.subscriptions.order(:created_at).last

      event.update!(subscription_id: subscription.id)
    end
  end
end
