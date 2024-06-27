# frozen_string_literal: true

module Integrations
  module Aggregator
    class PerformSyncJob < ApplicationJob
      queue_as 'integrations'

      retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3

      def perform(integration:, sync_tax_items: false)
        sync_result = Integrations::Aggregator::SyncService.call(integration:)
        sync_result.raise_if_error!

        Integrations::Aggregator::FetchItemsJob.set(wait: 5.seconds).perform_later(integration:)

        if sync_tax_items
          Integrations::Aggregator::FetchTaxItemsJob.set(wait: 5.seconds).perform_later(integration:)
        end
      end
    end
  end
end
