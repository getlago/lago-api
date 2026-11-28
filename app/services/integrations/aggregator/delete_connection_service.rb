# frozen_string_literal: true

module Integrations
  module Aggregator
    # NOTE: Deletes the Nango connection of a destroyed QuickBooks integration, and the OAuth tokens it holds.
    #       Best effort: it runs inside a GraphQL request, so the HTTP client has short timeouts and no retry,
    #       and a failure never fails the destroy. Only the organization id, the provider config key,
    #       the error class and the status may reach a log.
    class DeleteConnectionService < BaseService
      Result = BaseResult

      def action_path
        "connection/#{ERB::Util.url_encode(integration.connection_id)}"
      end

      def call
        return result if integration.connection_id.blank?
        return result if connection_shared?

        http_client.delete(headers:, params: {provider_config_key: provider_key})
        result
      rescue LagoHttpClient::HttpError => e
        # A 404 means the connection is already gone.
        if e.error_code.to_i != 404
          log_delete_failure(e, status: e.error_code)
        end

        result
      rescue => e
        # Deliberately broad: a Nango failure, a timeout or a connect error must never fail the destroy.
        log_delete_failure(e)
        result
      end

      private

      # Deleting the connection must reach Nango even when it points at another company.
      def realm_id_mismatch_blocked?
        false
      end

      def http_client
        # max_retries: 0 turns off Net::HTTP's own retry of an idempotent DELETE after a read timeout.
        LagoHttpClient::Client.new(endpoint_url, open_timeout: 5, read_timeout: 10, write_timeout: 10, max_retries: 0)
      end

      # Across organizations: a connection id is global in Nango, so another integration may still use it.
      # The id is encrypted, so the rows are compared in Ruby, loading only the columns the check needs.
      def connection_shared?
        Integrations::QuickbooksIntegration.where.not(id: integration.id).select(:id, :type, :secrets).find_each.any? do |other|
          other.connection_id == integration.connection_id
        end
      end

      # Never the response body, the headers or the connection id: they can hold OAuth credentials.
      def log_delete_failure(error, status: nil)
        details = {
          organization_id: integration.organization_id,
          provider_config_key: provider_key,
          error: error.class.name,
          status:
        }.compact

        Rails.logger.warn("QuickBooks connection deletion failed #{details.to_json}")
      end
    end
  end
end
