# frozen_string_literal: true

module Public
  module V1
    class BaseController < ActionController::API
      wrap_parameters false
    end
  end
end
