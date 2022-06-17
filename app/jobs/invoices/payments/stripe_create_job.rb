# frozen_string_literal: true

module Invoices
  module Payments
    class StripeCreateJob < ApplicationJob
      queue_as 'billing'

      def perform(invoice)
        Invoices::Payments::StripeService.new(invoice).create
      end
    end
  end
end
