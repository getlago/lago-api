# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceJob < ApplicationJob
    queue_as :default

    def perform(charge:, event:)
      result = Fees::CreatePayInAdvanceService.call(charge:, event:)

      result.raise_if_error!
    end
  end
end
