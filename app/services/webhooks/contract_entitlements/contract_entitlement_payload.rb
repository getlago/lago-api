# frozen_string_literal: true

module Webhooks
  module ContractEntitlements
    # The object is the contract. The body is the render that the sender passes in `options[:contract_entitlement]`,
    # the same one as the activity log: a removed entitlement cannot be rendered after the write.
    module ContractEntitlementPayload
      RenderedBody = Data.define(:body) do
        def for_webhook! = self

        def serialize = body.to_h
      end

      private

      def object_serializer
        RenderedBody.new(body: options[:contract_entitlement])
      end

      def object_type
        "contract_entitlement"
      end
    end
  end
end
