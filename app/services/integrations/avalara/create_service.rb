# frozen_string_literal: true

module Integrations
  module Avalara
    class CreateService < BaseService
      Result = BaseResult[:integration]

      def initialize(params:)
        @params = params

        super
      end

      def call
        organization = Organization.find_by(id: params[:organization_id])

        unless organization.avalara_enabled?
          return result.not_allowed_failure!(code: "premium_integration_missing")
        end

        integration = Integrations::AvalaraIntegration.new(
          organization:,
          name: params[:name],
          code: params[:code],
          connection_id: params[:connection_id],
          account_id: params[:account_id],
          license_key: params[:license_key]
        )

        integration.save!

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :params
    end
  end
end
