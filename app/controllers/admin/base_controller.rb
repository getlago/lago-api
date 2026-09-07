# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include ApiErrors

    before_action :authenticate
    before_action :set_context_source

    private

    def authenticate
      key_header = request.headers["X-Admin-API-Key"]
      expected_key = ENV["ADMIN_API_KEY"]

      if key_header.present? && expected_key.present? && ActiveSupport::SecurityUtils.secure_compare(key_header, expected_key)
        CurrentContext.email = nil
        true
      else
        unauthorized_error
      end
    end

    def set_context_source
      CurrentContext.source = "admin"
      CurrentContext.api_key_id = nil
    end
  end
end
