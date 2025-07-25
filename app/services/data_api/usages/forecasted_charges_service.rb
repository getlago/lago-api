# frozen_string_literal: true

module DataApi
  module Usages
    class ForecastedChargesService < DataApi::BaseService
      Result = BaseResult[:forecasted_charges_usages]

      def call
        return result.forbidden_failure! unless License.premium?

        result.forecasted_charges_usages = http_client.get(headers:, params:)
        result
      end

      private

      def action_path
        "usages/#{organization.id}/forecasted/charges/"
      end
    end
  end
end
