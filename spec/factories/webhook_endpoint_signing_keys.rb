# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_endpoint_signing_key do
    webhook_endpoint
    organization { webhook_endpoint&.organization || association(:organization) }
  end
end
