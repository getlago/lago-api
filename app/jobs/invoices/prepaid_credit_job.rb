# frozen_string_literal: true

module Invoices
  class PrepaidCreditJob < ApplicationJob
    queue_as 'wallets'

    unique :until_executed, on_conflict: :log

    def perform(invoice)
      Wallets::ApplyPaidCreditsService.new.call(invoice)
      Invoices::FinalizeOpenCreditService.call(invoice:)
    end
  end
end
