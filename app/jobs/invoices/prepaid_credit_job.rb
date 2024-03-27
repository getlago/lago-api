# frozen_string_literal: true

module Invoices
  class PrepaidCreditJob < ApplicationJob
    queue_as "wallets"

    def perform(invoice)
      Wallets::ApplyPaidCreditsService.new.call(invoice)
    end
  end
end
