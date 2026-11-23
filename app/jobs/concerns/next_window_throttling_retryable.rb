# frozen_string_literal: true

module NextWindowThrottlingRetryable
  extend ActiveSupport::Concern

  NEXT_WINDOW_MAX_JITTER = 30 # seconds

  included do
    # NOTE: A rate limited job is waiting for its turn, not failing. It is retried once the window
    # has passed, with jitter to spread the backlog, and without an attempt cap.
    # `executions_for` is the ActiveJob internal `retry_on` uses: it counts these retries in
    # `exception_executions`, so a job can tell them apart from attempts that reached the provider.
    rescue_from(BaseService::NextWindowThrottlingError) do |error|
      executions_for([BaseService::NextWindowThrottlingError])

      retry_job(wait: error.retry_after + rand(0..NEXT_WINDOW_MAX_JITTER).seconds, error:)
    end
  end
end
