# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceJob < ApplicationJob
    queue_as :default

    def perform(charge:, event:, billing_at: nil)
      result = Fees::CreatePayInAdvanceService.call(charge:, event:, billing_at:)

      result.raise_if_error!
    end
  end
end
