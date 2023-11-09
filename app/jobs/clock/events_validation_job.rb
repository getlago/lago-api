# frozen_string_literal: true

module Clock
  class EventsValidationJob < ApplicationJob
    queue_as 'clock'

    def perform
      # NOTE: refresh the last hour events materialized view
      Scenic.database.refresh_materialized_view(
        Events::LastHourMv.table_name,
        concurrently: false,
        cascade: false,
      )

      # TODO: enqueue a validation jobs for each organization with at least one event
    end
  end
end
