# frozen_string_literal: true

module NextWindowThrottlingRetryable
  extend ActiveSupport::Concern

  NEXT_WINDOW_MAX_ATTEMPTS = 40
  NEXT_WINDOW_MAX_WINDOWS = 10
  NEXT_WINDOW_MAX_JITTER = 30 # seconds

  included do
    # NOTE: A rate limited job is waiting for its turn, not failing. It is retried once the current
    # window has passed, plus one more window per earlier retry (up to 10 minutes), with jitter to
    # spread the backlog. After 40 retries (about 6 hours) it stops, so a job that can never get a
    # slot reaches the dead set and the error tracker instead of retrying forever.
    # `executions_for` and `instrument` are the ActiveJob internals `retry_on` uses: the count lives in
    # `exception_executions`, so a job can tell these retries apart from attempts that reached the provider.
    rescue_from(BaseService::NextWindowThrottlingError) do |error|
      attempts = executions_for([BaseService::NextWindowThrottlingError])

      if attempts >= NEXT_WINDOW_MAX_ATTEMPTS
        instrument(:retry_stopped, error:)
        raise error
      end

      extra_windows = [attempts, NEXT_WINDOW_MAX_WINDOWS].min - 1
      wait = error.retry_after + (extra_windows * BaseService::NextWindowThrottlingError::DEFAULT_RETRY_AFTER)

      retry_job(wait: wait + rand(0..NEXT_WINDOW_MAX_JITTER).seconds, error:)
    end
  end
end
