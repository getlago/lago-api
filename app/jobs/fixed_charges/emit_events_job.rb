# frozen_string_literal: true

module FixedCharges
  class EmitEventsJob < ApplicationJob
    queue_as :default

    def perform(subscriptions:)
      FixedCharges::EmitEventsService.call(subscriptions:)
    end
  end
end
