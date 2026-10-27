# frozen_string_literal: true

module Api
  module V1
    # Parent of every v1 controller, for the behaviour only v1 controllers share.
    class BaseController < Api::BaseController
      # The v1 error body, which the /api/v2 fallback routes keep too.
      include ApiErrors

      # Also runs on the /api/v2 fallback routes, which serve these same controllers.
      before_action :validate_pagination_params
    end
  end
end
