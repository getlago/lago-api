# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Payments
  class ManualCreateJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
        :payments
      else
        :low_priority
      end
    end

    def perform(organization:, params:)
      Payments::ManualCreateService.call!(organization:, params:)
    end
  end
end
