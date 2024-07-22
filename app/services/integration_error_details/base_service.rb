# frozen_string_literal: true

module IntegrationErrorDetails
  class BaseService < BaseService
    def initialize(params:, error_producer:, owner:)
      @params = params
      @error_producer = error_producer
      @owner = owner

      super
    end

    def call
      result.not_found_failure!(resource: 'error_producer') unless error_producer
      result.not_found_failure!(resource: 'owner') unless owner
      result
    end

    private

    attr_reader :params, :error_producer, :owner
  end
end
