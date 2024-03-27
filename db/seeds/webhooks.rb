# frozen_string_literal: true

require "faker"
require "factory_bot_rails"

organization = Organization.find_or_create_by!(name: "Hooli")

webhook_endpoint = WebhookEndpoint.find_or_create_by!(organization:, webhook_url: "http://test.lago.dev/webhook")

3.times do
  FactoryBot.create(:webhook, :succeeded, webhook_endpoint:)
  FactoryBot.create(:webhook, :succeeded_with_retries, webhook_endpoint:)
  FactoryBot.create(:webhook, :failed, webhook_endpoint:)
  FactoryBot.create(:webhook, :failed_with_retries, webhook_endpoint:)
  FactoryBot.create(:webhook, :pending, webhook_endpoint:)
end
