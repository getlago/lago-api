# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class ProcessPaymentJob < ApplicationJob
      queue_as "default"

      def perform(invoice, payment_status)
        Subscriptions::ActivationRules::ProcessPaymentService.call!(invoice:, payment_status:)
      end
    end
  end
end
