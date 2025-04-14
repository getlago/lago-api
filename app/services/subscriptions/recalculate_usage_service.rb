# frozen_string_literal: true

module Subscriptions
  class RecalculateUsageService < BaseService
    def initialize(subscription:)
      @subscription = subscription
      super
    end

    def call
      # TODO: Implement
      result
    end

    private

    attr_reader :subscription
  end
end
