# frozen_string_literal: true

module Invoices
  class FinalizeJob < ApplicationJob
    queue_as 'invoices'

    def perform(invoice)
      Invoices::RefreshDraftAndFinalizeService.call(invoice:)
    end
  end
end
