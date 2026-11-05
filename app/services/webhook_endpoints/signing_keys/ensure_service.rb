# frozen_string_literal: true

module WebhookEndpoints
  module SigningKeys
    class EnsureService < BaseService
      Result = BaseResult[:signing_key]

      def initialize(webhook_endpoint:)
        @webhook_endpoint = webhook_endpoint

        super
      end

      # Callers hold the endpoint row lock, so the check and the create cannot race.
      def call
        result.signing_key = webhook_endpoint.signing_keys.usable.order(:created_at, :id).first ||
          webhook_endpoint.signing_keys.create!(organization: webhook_endpoint.organization)
        result
      end

      private

      attr_reader :webhook_endpoint
    end
  end
end
