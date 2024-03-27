# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    include Pagination
    include Common
    include ApiErrors

    before_action :authenticate
    before_action :set_context_source
    include Trackable

    rescue_from ActionController::ParameterMissing, with: :bad_request_error

    private

    def authenticate
      auth_header = request.headers["Authorization"]

      return unauthorized_error unless auth_header

      api_key = auth_header.split(" ").second

      return unauthorized_error unless api_key
      return unauthorized_error unless current_organization(api_key)

      true
    end

    def current_organization(api_key = nil)
      @current_organization ||= Organization.find_by(api_key:)
    end

    def set_context_source
      CurrentContext.source = "api"
    end
  end
end
