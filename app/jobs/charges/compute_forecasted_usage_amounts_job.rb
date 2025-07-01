# frozen_string_literal: true

module Charges
  class ComputeForecastedUsageAmountsJob < ApplicationJob
    queue_as :low_priority

    # TODO: retry_on ... how many times?

    def perform(organization:)
      Charges::ComputeForecastedUsageAmountsService.call!(organization:)
    end
  end
end
