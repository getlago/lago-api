# frozen_string_literal: true

module Invoices
  module Payments
    class CancelAbandonedJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      def perform(payment)
        Invoices::Payments::CancelAbandonedService.call!(payment:)
      end
    end
  end
end
