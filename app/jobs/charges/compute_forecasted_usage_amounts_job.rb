# frozen_string_literal: true

module Charges
  class ComputeForecastedUsageAmountsJob < ApplicationJob
    queue_as :low_priority

    def perform(organization:)
      Charges::ComputeForecastedUsageAmountsService.call!(organization:)
    end
  end
end
