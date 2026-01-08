# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceFixedChargesJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(subscription, timestamp)
      Invoices::CreatePayInAdvanceFixedChargesService.call!(
        subscription:,
        timestamp:
      )
    end
  end
end
