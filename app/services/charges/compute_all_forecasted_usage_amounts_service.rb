# frozen_string_literal: true

module Charges
  class ComputeAllForecastedUsageAmountsService < BaseService
    def call
      organizations.each do |organization|
        Charges::ComputeForecastedUsageAmountsJob.perform_later(organization)
      end

      result
    end

    private

    def organizations
      @organizations ||= Organization.with_forecasted_usage_support
    end
  end
end
