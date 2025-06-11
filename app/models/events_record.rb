# frozen_string_literal: true

class EventsRecord < ApplicationRecord
  self.abstract_class = true

  reading_db = ActiveModel::Type::Boolean.new.cast(ENV["USE_READ_REPLICA"]) ? :events_replica : :events
  connects_to database: {writing: :events, reading: reading_db}
end
