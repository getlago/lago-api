# frozen_string_literal: true

module DataApi
  module Usages
    class UpdateForecastedAmountsService < DataApi::BaseService
      def initialize(organization, **params)
        @usage_amounts = params[:usage_amounts]

        super
      end

      def call
        return result.forbidden_failure! unless License.premium?

        http_client.put_with_response(usage_amounts, headers)

        result
      rescue LagoHttpClient::HttpError => e
        result.service_failure!(code: e.error_code, message: e.error_body)
      end

      private

      attr_reader :usage_amounts

      def action_path
        "usages/#{organization.id}/forecasted/amounts/"
      end
    end
  end
end
