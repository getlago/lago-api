# frozen_string_literal: true

namespace :migrations do
  desc "Backfill last_received_event_on for active subscriptions from the events database"
  task fill_last_received_event_on: :environment do
    organization_ids = Organization
      .joins(:subscriptions)
      .where(subscriptions: {status: :active, last_received_event_on: nil})
      .distinct
      .pluck(:id)

    organization_ids.each { |id| DatabaseMigrations::BackfillLastReceivedEventOnJob.perform_later(id) }

    puts "Enqueued #{organization_ids.size} BackfillLastReceivedEventOnJob jobs."
  end
end
