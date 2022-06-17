# frozen_string_literal: true

module Invoices
  module Payments
    class StripeCreateJob < ApplicationJob
      queue_as 'billing'

      def perform(invoice)
        result = Invoices::Payments::StripeService.new(invoice).create
        result.throw_error unless result.success?
      end
    end
  end
end
