# frozen_string_literal: true

namespace :events do
  # NOTE: related to https://github.com/getlago/lago-api/issues/317
  desc 'Fill missing timestamps for events'
  task fill_timestamp: :environment do
    Event.where(timestamp: nil).find_each do |event|
      event.update!(timestamp: event.created_at)
    end
  end
end
