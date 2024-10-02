# frozen_string_literal: true

module Integrations
  module Aggregator
    class SyncCustomObjectsAndPropertiesJob < ApplicationJob
      queue_as 'integrations'

      def perform(integration:)
        Integrations::Hubspot::Objects::DeploySubscriptionsJob.perform_later(integration:)
        Integrations::Hubspot::Objects::DeployInvoicesJob.perform_later(integration:)
        Integrations::Hubspot::Properties::DeployCompaniesJob.perform_later(integration:)
        Integrations::Hubspot::Properties::DeployContactsJob.perform_later(integration:)
      end
    end
  end
end
