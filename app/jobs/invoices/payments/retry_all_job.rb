# frozen_string_literal: true

module Invoices
  module Payments
    class RetryAllJob < ApplicationJob
      queue_as 'invoices'

      def perform(organization_id:, invoice_ids:)
        result = Invoices::Payments::RetryBatchService.new(organization_id: organization_id).retry_all(invoice_ids)
        result.throw_error unless result.success?
      end
    end
  end
end
