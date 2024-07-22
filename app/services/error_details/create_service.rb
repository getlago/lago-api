# frozen_string_literal: true

module ErrorDetails
  class CreateService < BaseService
    def initialize(params:, integration: nil, owner:)
      super(params:, integration:, owner:)
    end

    def call
      result = super
      return result if result.error

      res = create_error_details!
      return res if res&.error

      res
    end

    private

    def create_error_details!
      new_error = ErrorDetail.create!(
        integration:,
        owner:,
        details: params[:details]
      )

      result.error_details = new_error
      result
    end
  end
end
