# frozen_string_literal: true

module Integrations
  module Aggregator
    class AccountInformationService < BaseService
      Result = BaseResult[:account_information]

      AccountInformation = Data.define(:id)

      # NOTE: Nango HubSpot template. Older versions return the portal id as `id`, newer ones as `portalId`
      def action_name
        "fetch-account-information"
      end

      def call
        throttle!(:hubspot)

        response = JSON.parse(trigger_action({}).body)

        portal_id = response["id"].presence || response["portalId"]&.to_s
        result.account_information = AccountInformation.new(id: portal_id)
        result
      end
    end
  end
end
