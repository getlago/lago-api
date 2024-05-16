# frozen_string_literal: true

require 'lago_http_client'

module Integrations
  module Aggregator
    class BaseService < BaseService
      BASE_URL = 'https://api.nango.dev/'

      def initialize(integration:, options: {})
        @integration = integration
        @options = options

        super
      end

      def action_path
        raise NotImplementedError
      end

      private

      attr_reader :integration, :options

      # NOTE: Extend it with other providers if needed
      def provider
        case integration.type
        when 'Integrations::NetsuiteIntegration'
          'netsuite'
        end
      end

      def http_client
        LagoHttpClient::Client.new(endpoint_url)
      end

      def endpoint_url
        "#{BASE_URL}#{action_path}"
      end

      def headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}",
        }
      end

      def tax_item
        @tax_item ||= integration.integration_collection_mappings.where(mapping_type: :tax)&.first
      end

      def commitment_item
        @tax_item ||= integration.integration_collection_mappings.where(mapping_type: :minimum_commitment)&.first
      end

      def subscription_item
        @tax_item ||= integration.integration_collection_mappings.where(mapping_type: :subscription_fee)&.first
      end

      def coupon_item
        @tax_item ||= integration.integration_collection_mappings.where(mapping_type: :coupon)&.first
      end

      def credit_item
        @tax_item ||= integration.integration_collection_mappings.where(mapping_type: :prepaid_credit)&.first
      end

      def credit_note_item
        @tax_item ||= integration.integration_collection_mappings.where(mapping_type: :credit_note)&.first
      end

      def fallback_item
        @fallback_item ||= integration.integration_collection_mappings.where(mapping_type: :fallback_item)&.first
      end

      def amount(amount_cents)
        currency = invoice.total_amount.currency

        amount_cents.round.fdiv(currency.subunit_to_unit)
      end

      def secret_key
        ENV['NANGO_SECRET_KEY']
      end
    end
  end
end
