# frozen_string_literal: true

module ManualPayments
  class CreateJob < ApplicationJob
    queue_as "low_priority"

    def perform(organization:, params:, skip_checks: false)
      ManualPayments::CreateService.call!(organization:, params:, skip_checks:)
    end
  end
end
