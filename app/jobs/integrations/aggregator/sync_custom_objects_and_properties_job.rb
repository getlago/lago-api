# frozen_string_literal: true

module Integrations
  module Aggregator
    class SyncCustomObjectsAndPropertiesJob < ApplicationJob
      queue_as 'integrations'

      def perform(integration:)
        Integrations::Hubspot::Invoices::DeployObjectJob.perform_later(integration:)
        Integrations::Hubspot::Subscriptions::DeployObjectJob.perform_later(integration:)
        Integrations::Hubspot::Companies::DeployPropertiesJob.perform_later(integration:)
        Integrations::Hubspot::Contacts::DeployPropertiesJob.perform_later(integration:)
      end
    end
  end
end
