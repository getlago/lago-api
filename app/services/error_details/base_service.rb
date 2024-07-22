# frozen_string_literal: true

module ErrorDetails
  class BaseService < BaseService
    def initialize(params:, integration: nil, owner:)
      @params = params
      @integration = integration
      @owner = owner

      super
    end

    def call
      result.not_found_failure!(resource: 'owner') unless owner
      result
    end

    private

    attr_reader :params, :integration, :owner
  end
end
