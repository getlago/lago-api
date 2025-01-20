# frozen_string_literal: true

module Payments
  class ManualCreateJob < ApplicationJob
    queue_as "low_priority"

    def perform(organization:, params:)
      Payments::ManualCreateService.call!(organization:, params:)
    end
  end
end
