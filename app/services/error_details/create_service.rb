# frozen_string_literal: true

module ErrorDetails
  class CreateService < BaseService

    def call
      result = super
      return result unless result.success?

      create_error_details!
    end

    private

    def create_error_details!
      new_error = ErrorDetail.create!(
        integration:,
        owner:,
        organization:,
        error_code: params[:error_code],
        details: params[:details]
      )

      result.error_details = new_error
      result
    rescue ArgumentError => e
      result.validation_failure!(errors: e.message)
    end
  end
end
