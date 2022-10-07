# frozen_string_literal: true

module CreditNotes
  class GeneratePdfJob < ApplicationJob
    queue_as 'invoices'

    def perform(credit_note)
      CreditNotes::GenerateService.new.call_from_api(credit_note: credit_note)
    end
  end
end
