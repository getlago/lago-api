# frozen_string_literal: true

module Subscriptions
  class EmitFixedChargesEventsJob < ApplicationJob
    queue_as :default

    def perform(subscriptions:)
      Subscriptions::EmitFixedChargesEventsService.call(subscriptions:)
    end
  end
end
