# frozen_string_literal: true

class ApplicationController < ActionController::API
  def health
    render json: { message: 'Success' }, status: :ok
  end
end
