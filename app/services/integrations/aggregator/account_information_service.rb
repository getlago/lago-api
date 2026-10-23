# frozen_string_literal: true

module Integrations
  module Aggregator
    class AccountInformationService < BaseService
      Result = BaseResult[:account_information]

      AccountInformation = Data.define(:id)

      # NOTE: Nango HubSpot template, v1 returns the portal id as `id`
      def action_name
        "fetch-account-information"
      end

      def call
        throttle!(:hubspot)

        response = JSON.parse(trigger_action({}).body)

        result.account_information = AccountInformation.new(id: response["id"])
        result
      end
    end
  end
end
