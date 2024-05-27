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
          'Authorization' => "Bearer #{secret_key}"
        }
      end

      def deliver_error_webhook(customer:, code:, message:)
        SendWebhookJob.perform_later(
          'customer.accounting_provider_error',
          customer,
          provider:,
          provider_code: integration.code,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def tax_item
        @tax_item ||= collection_mapping(:tax) || fallback_item
      end

      def commitment_item
        @commitment_item ||= collection_mapping(:minimum_commitment) || fallback_item
      end

      def subscription_item
        @subscription_item ||= collection_mapping(:subscription_fee) || fallback_item
      end

      def coupon_item
        @coupon_item ||= collection_mapping(:coupon) || fallback_item
      end

      def credit_item
        @credit_item ||= collection_mapping(:prepaid_credit) || fallback_item
      end

      def credit_note_item
        @credit_note_item ||= collection_mapping(:credit_note) || fallback_item
      end

      def fallback_item
        @fallback_item ||= collection_mapping(:fallback_item)
      end

      def amount(amount_cents)
        currency = invoice.total_amount.currency

        amount_cents.round.fdiv(currency.subunit_to_unit)
      end

      def collection_mapping(type)
        integration.integration_collection_mappings.where(mapping_type: type)&.first
      end

      def secret_key
        ENV['NANGO_SECRET_KEY']
      end
    end
  end
end
