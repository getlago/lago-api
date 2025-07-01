# frozen_string_literal: true

module DataApi
  module Usages
    class UpdateForecastedAmountsJob < ApplicationJob
      queue_as :low_priority

      retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3

      def perform(usage_amounts)
        DataApi::Usages::UpdateForecastedAmountsService.call!(usage_amounts:)
      end
    end
  end
end
