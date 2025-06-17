# frozen_string_literal: true

module Subscriptions
  class EmitFixedChargesEventsService < BaseService
    def initialize(subscriptions:)
      @subscriptions = subscriptions
    end

    def call
      subscriptions.each do |subscription|
        subscription.fixed_charges.each do |fixed_charge|
          FixedCharges::EmitEventsService.call(fixed_charge:, subscription:)
        end
      end
    end
  end
end