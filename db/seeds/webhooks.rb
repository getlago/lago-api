# frozen_string_literal: true

require 'faker'
require 'factory_bot_rails'

organization = Organization.find_or_create_by!(name: 'Hooli')

3.times do
  FactoryBot.create(:webhook, :succeeded, organization:)
  FactoryBot.create(:webhook, :succeeded_with_retries, organization:)
  FactoryBot.create(:webhook, :failed, organization:)
  FactoryBot.create(:webhook, :failed_with_retries, organization:)
  FactoryBot.create(:webhook, :pending, organization:)
end
