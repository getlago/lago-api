# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Invoices
  class RetryAllJob < ApplicationJob
    queue_as "invoices"

    def perform(organization:, invoice_ids:)
      result = Invoices::RetryBatchService.new(organization:).call(invoice_ids)
      result.raise_if_error!
    end
  end
end
