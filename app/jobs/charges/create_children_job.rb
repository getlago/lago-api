# frozen_string_literal: true

module Charges
  class CreateChildrenJob < ApplicationJob
    queue_as "default"

    def perform(charge:, payload:)
      Charges::CreateChildrenService.call!(charge:, payload:)
    end
  end
end
