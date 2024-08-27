# frozen_string_literal: true

module PaymentRequests
  module Payments
    class GocardlessCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed

      def perform(payable)
        result = PaymentRequests::Payments::GocardlessService.new(payable).create
        result.raise_if_error!
      end
    end
  end
end
