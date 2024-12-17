# frozen_string_literal: true

module PaymentRequests
  module Payments
    class GocardlessCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed, on_conflict: :log

      def perform(payable)
        PaymentRequests::Payments::CreateService.call!(payable:, payment_provider: 'gocardless')
      end
    end
  end
end
