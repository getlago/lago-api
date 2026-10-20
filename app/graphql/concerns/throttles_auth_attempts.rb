# frozen_string_literal: true

# Helpers for the public auth mutations throttled with ::Auth::AttemptsThrottle.
module ThrottlesAuthAttempts
  extend ActiveSupport::Concern

  private

  def client_ip
    context[:request]&.remote_ip
  end

  def too_many_attempts_error
    execution_error(error: "Too Many Requests", status: 429, code: "too_many_requests")
  end
end
