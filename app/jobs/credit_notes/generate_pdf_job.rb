# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module CreditNotes
  class GeneratePdfJob < ApplicationJob
    queue_as "invoices"

    def perform(credit_note)
      result = CreditNotes::GeneratePdfService.call(credit_note:, context: "api")
      result.raise_if_error!
    end
  end
end
