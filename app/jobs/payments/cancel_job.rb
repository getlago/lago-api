# frozen_string_literal: true

module Payments
  class CancelJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
        :payments
      else
        :providers
      end
    end

    def perform(payment)
      Payments::CancelService.call!(payment:)
    end
  end
end
