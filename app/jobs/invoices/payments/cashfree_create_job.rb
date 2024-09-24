# frozen_string_literal: true

module Invoices
  module Payments
    class CashfreeCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed

      def perform(invoice)
        result = Invoices::Payments::CashfreeService.new(invoice).create
        result.raise_if_error!
      end
    end
  end
end
