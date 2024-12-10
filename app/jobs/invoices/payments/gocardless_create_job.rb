# frozen_string_literal: true

module Invoices
  module Payments
    class GocardlessCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed, on_conflict: :log

      def perform(invoice)
        # NOTE: Legacy job, kept only to avoid existing jobs

        Invoices::Payments::CreateService.call!(invoice:, payment_provider: :gocardless)
      end
    end
  end
end
