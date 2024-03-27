# frozen_string_literal: true

module Invoices
  class GeneratePdfJob < ApplicationJob
    queue_as "invoices"

    def perform(invoice)
      result = Invoices::GeneratePdfService.call(invoice:, context: "api")
      result.raise_if_error!
    end
  end
end
