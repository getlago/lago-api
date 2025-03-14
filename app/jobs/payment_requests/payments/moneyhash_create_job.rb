# frozen_string_literal: true

module PaymentRequests
  module Payments
    class MoneyhashCreateJob < ApplicationJob
      queue_as "providers"

      unique :until_executed

      def perform(payable)
        result = PaymentRequests::Payments::MoneyhashService.new(payable).create
        result.raise_if_error!
      end
    end
  end
end
