# frozen_string_literal: true

namespace :events do
  # NOTE: related to https://github.com/getlago/lago-api/issues/317
  desc 'Fill missing timestamps for events'
  task fill_timestamp: :environment do
    Event.unscoped.where(timestamp: nil).find_each do |event|
      event.update!(timestamp: event.created_at)
    end
  end

  desc 'Fill missing subscription_id'
  task fill_subscription: :environment do
    Event.unscoped.where(subscription_id: nil).find_each do |event|
      subscription = event.customer.active_subscription || event.customer.subscriptions.order(:created_at).last

      unless subscription
        event.destroy
        next
      end

      event.update!(subscription_id: subscription.id)
    end
  end

  desc 'Fill missing properties on persisted_events'
  task fill_persisted_properties: :environment do
    PersistedEvent.unscoped.find_each do |persisted_event|
      event = Event.unscoped.where(
        organization_id: persisted_event.billable_metric.organization_id,
        customer_id: persisted_event.customer_id,
      ).where(
        "properties -> '#{persisted_event.billable_metric.field_name}' = ?",
        persisted_event.external_id,
      ).first

      persisted_event.update!(properties: event.properties)
    end
  end
end
