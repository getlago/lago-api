# frozen_string_literal: true

module Invoices
  module Payments
    class GocardlessCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed, on_conflict: :log

      def perform(invoice)
        # NOTE: Legacy job, kept only to avoid existing jobs

        result = Invoices::Payments::GocardlessService.call(invoice)
        result.raise_if_error!
      end
    end
  end
end
