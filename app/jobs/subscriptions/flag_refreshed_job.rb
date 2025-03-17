# frozen_string_literal: true

module Subscriptions
  class FlagRefreshedJob < ApplicationJob
    queue_as :events

    def perform(payload)
      Subscriptions::FlagRefreshedService.call!(payload)
    end
  end
end
