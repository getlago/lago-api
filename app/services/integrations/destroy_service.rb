# frozen_string_literal: true

module Integrations
  class DestroyService < BaseService
    def initialize(integration:)
      @integration = integration

      super
    end

    def call
      return result.not_found_failure!(resource: "integration") unless integration

      integration.destroy!

      result.integration = integration
      result
    end

    private

    attr_reader :integration
  end
end
