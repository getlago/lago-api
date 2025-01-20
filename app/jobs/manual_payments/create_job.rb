# frozen_string_literal: true

module ManualPayments
  class CreateJob < ApplicationJob
    queue_as "low_priority"

    def perform(organization:, params:)
      ManualPayments::CreateService.call!(organization:, params:)
    end
  end
end
