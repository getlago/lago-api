# frozen_string_literal: true

module WebhookEndpoints
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      webhook_endpoint = organization.webhook_endpoints.new(
        webhook_url: params[:webhook_url],
      )

      webhook_endpoint.save!

      result.webhook_endpoint = webhook_endpoint
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
