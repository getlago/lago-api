# frozen_string_literal: true

module Organizations
  class TerminateService < BaseService
    def initialize(organization:)
      @organization = organization
      super
    end

    def call
      return result.not_found_failure!(resource: 'organization') unless organization

      ActiveRecord::Base.transaction do
        organization.reload
        organization.api_keys.destroy_all
        organization.webhooks.each(&:destroy!)
        organization.webhook_endpoints.destroy_all

        organization.destroy!
      end

      result.organization = organization
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization
  end
end
