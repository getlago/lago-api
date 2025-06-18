# frozen_string_literal: true

module FixedCharges
  class CreateChildrenJob < ApplicationJob
    queue_as "default"

    def perform(fixed_charge:, payload:)
      FixedCharges::CreateChildrenService.call!(fixed_charge:, payload:)
    end
  end
end
