# frozen_string_literal: true

module Integrations
  module NetsuiteV2
    class CreateService < BaseService
      attr_reader :params

      def initialize(params:)
        @params = params

        super
      end

      def call
        organization = Organization.find_by(id: params[:organization_id])

        unless organization.netsuite_v2_enabled?
          return result.not_allowed_failure!(code: "premium_integration_missing")
        end

        integration = Integrations::NetsuiteV2Integration.new(
          organization:,
          name: params[:name],
          code: params[:code],
          client_id: params[:client_id],
          client_secret: params[:client_secret],
          account_id: params[:account_id],
          token_id: params[:token_id],
          token_secret: params[:token_secret],
          script_endpoint_url: params[:script_endpoint_url],
          sync_credit_notes: ActiveModel::Type::Boolean.new.cast(params[:sync_credit_notes]),
          sync_invoices: ActiveModel::Type::Boolean.new.cast(params[:sync_invoices]),
          sync_payments: ActiveModel::Type::Boolean.new.cast(params[:sync_payments])
        )

        integration.save!

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
