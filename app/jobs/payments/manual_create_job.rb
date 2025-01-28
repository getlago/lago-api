# frozen_string_literal: true

module Payments
  class ManualCreateJob < ApplicationJob
    queue_as "low_priority"

    def perform(organization:, params:, skip_checks: false)
      Payments::ManualCreateService.call!(organization:, params:, skip_checks:)
    end
  end
end
