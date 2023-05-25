# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeJob < ApplicationJob
    queue_as 'billing'

    retry_on Sequenced::SequenceError

    def perform(charge:, event:, timestamp:)
      result = Invoices::CreatePayInAdvanceChargeService.call(charge:, event:, timestamp:)

      result.raise_if_error!
    end
  end
end
