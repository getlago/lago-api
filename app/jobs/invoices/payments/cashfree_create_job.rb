# frozen_string_literal: true

module Invoices
  module Payments
    class CashfreeCreateJob < ApplicationJob
      queue_as "providers"

      unique :until_executed

      def perform(invoice)
        Invoices::Payments::CashfreeService.call!(invoice)
      end
    end
  end
end
