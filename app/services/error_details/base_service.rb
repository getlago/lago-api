# frozen_string_literal: true

module ErrorDetails
  class BaseService < BaseService
    def initialize(params:, owner:, organization:, integration: nil)
      @params = params
      @integration = integration
      @owner = owner
      @organization = organization

      super
    end

    def call
      result.not_found_failure!(resource: 'owner') unless owner
      result.not_found_failure!(resource: 'organization') unless organization
      result
    end

    private

    attr_reader :params, :integration, :owner, :organization
  end
end
