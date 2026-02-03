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

      update_params = {}
      update_params[:webhook_url] = params[:webhook_url] if params.has_key?(:webhook_url)
      update_params[:signature_algo] = params[:signature_algo].to_sym if params.has_key?(:signature_algo)
      update_params[:name] = params[:name] if params.has_key?(:name)
      update_params[:event_types] = params[:event_types] if params.has_key?(:event_types)

      webhook_endpoint.update!(update_params)

      result.webhook_endpoint = webhook_endpoint
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :id, :organization, :params
  end
end
