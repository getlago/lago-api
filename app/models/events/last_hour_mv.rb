# frozen_string_literal: true

module Events
  class LastHourMv < ApplicationRecord
    self.table_name = 'last_hour_events_mv'

    def readonly?
      true
    end
  end
end
