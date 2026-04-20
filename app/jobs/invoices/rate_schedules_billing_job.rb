# frozen_string_literal: true

module Invoices
  class RateSchedulesBillingJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(rate_schedules, timestamp, invoicing_reason:)
      Invoices::RateSchedulesBillingService.new(
        rate_schedules,
        timestamp,
        invoicing_reason:
      ).call
    end
  end
end
