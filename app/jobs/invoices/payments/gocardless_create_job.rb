# frozen_string_literal: true

module Invoices
  module Payments
    class GocardlessCreateJob < ApplicationJob
      queue_as "providers"

      unique :until_executed

      def perform(invoice)
        result = Invoices::Payments::GocardlessService.new(invoice).create
        result.raise_if_error!
      end
    end
  end
end
