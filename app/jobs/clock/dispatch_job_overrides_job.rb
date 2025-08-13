# frozen_string_literal: true

module Clock
  class DispatchJobOverridesJob < ClockJob
    UnknownJobError = Class.new(StandardError)

    unique :until_executed, on_conflict: :log

    def perform
      JobScheduleOverride.enabled.find_each do |override|
        next unless override.due_to_run?

        dispatch(override)
      end
    end

    private

    def dispatch(override)
      unless override.job_klass
        msg = "[DispatchJobOverridesJob] Unknown job name: #{override.job_name}"
        Rails.logger.error(msg)
        raise UnknownJobError.new(msg)
      end

      override.job_klass.perform_later(organization: override.organization)
      override.update!(last_enqueued_at: Time.current)
    rescue StandardError => e
      msg = "[DispatchJobOverridesJob] Error dispatching #{override.id}: #{e.message}"
      Rails.logger.error(msg)
      Sentry.capture_exception(e) if defined?(Sentry)
    end
  end
end
