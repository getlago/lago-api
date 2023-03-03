# frozen_string_literal: true

module Fees
  class CreateInstantJob < ApplicationJob
    queue_as :default

    def perform(charge:, event:)
      result = Fees::CreateInstantService.call(charge:, event:)

      result.raise_if_error!
    end
  end
end
