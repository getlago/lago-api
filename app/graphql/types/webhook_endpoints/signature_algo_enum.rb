# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module WebhookEndpoints
    class SignatureAlgoEnum < Types::BaseEnum
      graphql_name "WebhookEndpointSignatureAlgoEnum"

      WebhookEndpoint::SIGNATURE_ALGOS.each do |type|
        value type
      end
    end
  end
end
