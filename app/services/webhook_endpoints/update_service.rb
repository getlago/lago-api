# frozen_string_literal: true

module WebhookEndpoints
  class UpdateService < BaseService
    def initialize(id:, organization:, params:)
      @id = id
      @organization = organization
      @params = params

      super
    end

    def call
      webhook_endpoint = organization.webhook_endpoints.find_by(id:)

      return result.not_found_failure!(resource: "webhook_endpoint") if webhook_endpoint.blank?

      webhook_endpoint.update!(
        webhook_url: params[:webhook_url],
        signature_algo: params[:signature_algo]
      )

      result.webhook_endpoint = webhook_endpoint
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :id, :organization, :params
  end
end
