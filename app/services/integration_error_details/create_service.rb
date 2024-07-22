# frozen_string_literal: true

module IntegrationErrorDetails
  class CreateService < BaseService
    def initialize(params:, error_producer:, owner:)
      @error_producer = error_producer
      @owner = owner
      super(params:, error_producer:, owner:)
    end

    def call
      result = super
      return result if result.error

      res = create_integration_error_details!
      return res if res&.error

      res
    end

    private

    attr_reader :error_producer, :owner

    def create_integration_error_details!
      new_integration_error = IntegrationErrorDetail.create!(
        error_producer:,
        owner:,
        details: params[:details]
      )

      result.integration_error_details = new_integration_error
      result
    end
  end
end
