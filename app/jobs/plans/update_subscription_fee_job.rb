# frozen_string_literal: true

module Plans
  class UpdateSubscriptionFeeJob < ApplicationJob
    queue_as 'default'

    def perform(plan:, amount_cents:)
      Plans::UpdateSubscriptionFeeService.call(plan:, amount_cents:)
    end
  end
end
