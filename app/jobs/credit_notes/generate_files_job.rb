# frozen_string_literal: true

module CreditNotes
  class GenerateFilesJob < ApplicationJob
    queue_as "invoices"

    def perform(credit_note)
      CreditNotes::GenerateXmlService.call(credit_note:, context: "api").raise_if_error!
      CreditNotes::GenerateService.call(credit_note:, context: "api").raise_if_error!
    end
  end
end
