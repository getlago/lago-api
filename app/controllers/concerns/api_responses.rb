# frozen_string_literal: true

module ApiResponses
  extend ActiveSupport::Concern

  included do
    before_action :set_json_format
  end

  def not_found_error(message:)
    render(
      json: {
        status: 404,
        error: 'Not Found',
        message: message,
      },
      status: :not_found,
    )
  end

  protected

  def set_json_format
    request.format = :json
  end
end
