# frozen_string_literal: true

module WebhookEndpoints
  module SigningKeys
    # Gives a standard_webhooks endpoint its signing key, reusing the one it already has.
    class CreateService < BaseService
      Result = BaseResult[:signing_key]

      def initialize(webhook_endpoint:)
        @webhook_endpoint = webhook_endpoint

        super
      end

      def call
        ActiveRecord::Base.transaction do
          # Serializes concurrent switches, so only one of them creates the key. Locks a separate
          # instance: lock! would reload the caller's record and clear its previous_changes.
          WebhookEndpoint.where(organization_id: webhook_endpoint.organization_id).lock.find(webhook_endpoint.id)

          result.signing_key = webhook_endpoint.current_signing_key ||
            webhook_endpoint.signing_keys.create!(organization_id: webhook_endpoint.organization_id)
        end

        result
      end

      private

      attr_reader :webhook_endpoint
    end
  end
end
