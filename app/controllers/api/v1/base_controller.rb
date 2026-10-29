# frozen_string_literal: true

module Api
  module V1
    # Parent of every v1 controller, for the behaviour only v1 controllers share.
    class BaseController < Api::BaseController
      # The v1 error body, which the /api/v2 fallback routes keep too.
      include Api::V1Errors

      # Api::V2::BaseController rescues a missing parameter with its own handler.
      rescue_from ActionController::ParameterMissing, with: :bad_request_error

      # Also runs on the /api/v2 fallback routes, which serve these same controllers.
      before_action :validate_pagination_params
    end
  end
end
