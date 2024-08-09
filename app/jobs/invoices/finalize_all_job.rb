# frozen_string_literal: true

module Invoices
  class FinalizeAllJob < ApplicationJob
    queue_as 'invoices'

    def perform(organization:, invoice_ids:)
      result = Invoices::FinalizeBatchService.new(organization:).call(invoice_ids)
      result.raise_if_error! unless tax_error?(result)
    end

    private

    def tax_error?(result)
      result.error&.messages&.dig(:tax_error)
    end
  end
end
