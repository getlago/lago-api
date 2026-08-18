# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    class RefreshAllJob < ApplicationJob
      queue_as :low_priority

      unique :until_executed, on_conflict: :log

      def perform(owner)
        Subscriptions::BillingPeriods::RefreshAllService.call!(owner:)
      end
    end
  end
end
