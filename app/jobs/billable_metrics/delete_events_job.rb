# frozen_string_literal: true

module BillableMetrics
  class DeleteEventsJob < ApplicationJob
    queue_as :default

    def perform(_metric)
      true
    end
  end
end
