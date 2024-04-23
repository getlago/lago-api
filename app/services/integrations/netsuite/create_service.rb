# frozen_string_literal: true

module Integrations
  module Netsuite
    class CreateService < BaseService
      def call(**args)
        organization = Organization.find_by(id: args[:organization_id])

        unless organization.premium_integrations.include?('netsuite')
          return result.not_allowed_failure!(code: 'premium_integration_missing')
        end

        integration = Integrations::NetsuiteIntegration.new(
          organization:,
          name: args[:name],
          code: args[:code],
          client_id: args[:client_id],
          client_secret: args[:client_secret],
          account_id: args[:account_id],
          connection_id: args[:connection_id],
          sync_credit_notes: ActiveModel::Type::Boolean.new.cast(args[:sync_credit_notes]),
          sync_invoices: ActiveModel::Type::Boolean.new.cast(args[:sync_invoices]),
          sync_payments: ActiveModel::Type::Boolean.new.cast(args[:sync_payments]),
          sync_sales_orders: ActiveModel::Type::Boolean.new.cast(args[:sync_sales_orders]),
        )

        integration.script_endpoint_url = args[:script_endpoint_url] if args.key?(:script_endpoint_url)

        integration.save!

        if integration.type == 'Integrations::NetsuiteIntegration'
          Integrations::Aggregator::SendRestletEndpointJob.perform_later(integration:)
        end

        Integrations::Aggregator::FetchItemsJob.perform_later(integration:)
        Integrations::Aggregator::FetchTaxItemsJob.perform_later(integration:)

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
