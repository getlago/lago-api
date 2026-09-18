# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateJob < ApplicationJob
        include ConcurrencyThrottlable
        include Integrations::Aggregator::ProviderDelayedRetry

        queue_as "integrations"

        unique :until_executed, on_conflict: :log

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3
        retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100
        retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25
        discard_on BaseService::NonRetryableFailure

        def perform(invoice:, find_first: false)
          # Note: Look upstream before posting in two cases:
          # - "find_first: true": caller (typically the manual SyncInvoice mutation) suspects
          #   the invoice is not in sync because a prior POST may have landed on NetSuite without
          #   us recording the IntegrationResource. Always reconcile before retrying.
          # - "executions > 1": any retry — a previous attempt may have contacted NetSuite
          #   and the safest assumption is that the record might already exist there.
          #   Skips a duplicate POST that would either fail NetSuite's tranid uniqueness
          #   or duplicate the invoice on Netsuite
          if find_first || executions > 1
            reconcile_result = Integrations::Aggregator::Invoices::ReconcileService.call!(invoice:)
            return if reconcile_result.external_id.present?
          end

          Integrations::Aggregator::Invoices::CreateService.call!(invoice:)
        end
      end
    end
  end
end
