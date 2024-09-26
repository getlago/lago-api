# frozen_string_literal: true

module Integrations
  module Hubspot
    class SyncCustomObjectsAndPropertiesJob < ApplicationJob
      queue_as 'integrations'

      def perform(integration:)
        # create objects
        Integrations::Hubspot::Objects::DeploySubscriptionsJob.perform_later(integration: integration)
        Integrations::Hubspot::Objects::DeployInvoicesJob.perform_later(integration: integration)

        # sync properties
        Integrations::Hubspot::Properties::DeployCompaniesJobs.perform_later(integration: integration)
        Integrations::Hubspot::Properties::DeployContactsJobs.perform_later(integration: integration)
      end
    end
  end
end