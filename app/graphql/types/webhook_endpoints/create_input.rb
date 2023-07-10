# frozen_string_literal: true

module Types
  module WebhookEndpoints
    class CreateInput < BaseInputObject
      graphql_name 'WebhookEndpointCreateInput'

      argument :webhook_url, String, required: true
    end
  end
end
