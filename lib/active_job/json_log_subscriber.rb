# frozen_string_literal: true

require "active_support/subscriber"
require "active_job/log_subscriber"

module ActiveJob
  class JsonLogSubscriber < ActiveSupport::LogSubscriber # :nodoc:
    # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    class_attribute :backtrace_cleaner, default: ActiveSupport::BacktraceCleaner.new
    # rubocop:enable ThreadSafety/ClassAndModuleAttributes

    def enqueue(event)
      job = event.payload[:job]
      ex = event.payload[:exception_object] || job.enqueue_error

      if ex
        enqueue_error(job, ex)
      elsif event.payload[:aborted]
        info do
          {
            level: "info",
            event: "enqueue",
            status: "aborted",
            job: job.class.name,
            queue: job.queue_name
          }.to_json
        end
      else
        enqueue_success(job)
      end
    end
    subscribe_log_level :enqueue, :info

    def enqueue_all(event)
      jobs = event.payload[:jobs]
      ex = event.payload[:exception_object]

      jobs.each do |job|
        job_ex = ex || job.enqueue_error
        if job_ex
          enqueue_error(job, job_ex)
        else
          extra = job.scheduled_at ? {enqueued_at: scheduled_at(job)} : {}
          enqueue_success(job, **extra)
        end
      end
    end

    def enqueue_at(event)
      job = event.payload[:job]
      ex = event.payload[:exception_object] || job.enqueue_error

      if ex
        enqueue_error(job, ex)
      elsif event.payload[:aborted]
        info do
          {
            level: "info",
            event: "enqueue",
            status: "aborted",
            job: job.class.name,
            queue: job.queue_name
          }.to_json
        end
      else
        enqueue_success(job, enqueued_at: scheduled_at(job))
      end
    end
    subscribe_log_level :enqueue_at, :info

    def perform_start(event)
      info do
        job = event.payload[:job]

        message = {
          level: "info",
          event: "perform",
          status: "start",
          job: job.class.name,
          job_id: job.job_id,
          arguments: args_info(job),
          queue: job.queue_name
        }

        job.enqueued_at ? message.merge(enqueued_at: job.enqueued_at.utc).to_json : message.to_json
      end
    end
    subscribe_log_level :perform_start, :info

    def perform(event)
      job = event.payload[:job]
      ex = event.payload[:exception_object]

      if ex
        error do
          {
            level: "error",
            event: "perform",
            status: "error",
            job: job.class.name,
            duration: event.duration.round(2),
            job_id: job.job_id,
            queue: job.queue_name,
            exception: {
              class: ex.class.name,
              message: ex.message
            }
          }.to_json
        end
      elsif event.payload[:aborted]
        info do
          {
            level: "info",
            event: "perform",
            status: "aborted",
            job: job.class.name,
            duration: event.duration.round(2),
            job_id: job.job_id,
            queue: job.queue_name
          }.to_json
        end
      else
        info do
          {
            level: "info",
            event: "perform",
            status: "success",
            job: job.class.name,
            duration: event.duration.round(2),
            job_id: job.job_id,
            queue: job.queue_name
          }.to_json
        end
      end
    end
    subscribe_log_level :perform, :info

    def enqueue_retry(event)
      job = event.payload[:job]
      ex = event.payload[:error]
      wait = event.payload[:wait]

      info do
        if ex
          {
            level: "error",
            event: "retry",
            status: "error",
            job: job.class.name,
            job_id: job.job_id,
            execution: job.executions,
            wait: wait.to_i,
            exception: {
              class: ex.class.name,
              message: ex.message
            }
          }.to_json
        else
          {
            level: "info",
            event: "retry",
            status: "success",
            job: job.class.name,
            job_id: job.job_id,
            execution: job.executions,
            wait: wait.to_i
          }.to_json
        end
      end
    end
    subscribe_log_level :enqueue_retry, :info

    def retry_stopped(event)
      job = event.payload[:job]
      ex = event.payload[:error]

      error do
        {
          level: "error",
          event: "retry",
          status: "stopped",
          job: job.class.name,
          job_id: job.job_id,
          queue: job.queue_name,
          retries: job.executions,
          exception: {
            class: ex.class.name,
            message: ex.message
          }
        }.to_json
      end
    end
    subscribe_log_level :retry_stopped, :error

    def discard(event)
      job = event.payload[:job]
      ex = event.payload[:error]

      error do
        {
          level: "error",
          event: "discard",
          status: "error",
          job: job.class.name,
          job_id: job.job_id,
          exception: {
            class: ex.class.name,
            message: ex.message
          }
        }.to_json
      end
    end
    subscribe_log_level :discard, :error

    private

    def args_info(job)
      if job.class.log_arguments? && job.arguments.any?
        job.arguments.map { |arg| format(arg).inspect }.join(", ")
      else
        {}
      end
    end

    def format(arg)
      case arg
      when Hash
        arg.transform_values { |value| format(value) }
      when Array
        arg.map { |value| format(value) }
      when GlobalID::Identification
        # rubocop:disable Style/RescueModifier
        arg.to_global_id rescue arg
        # rubocop:enable Style/RescueModifier
      else
        arg
      end
    end

    def scheduled_at(job)
      Time.at(job.scheduled_at).utc
    end

    def enqueue_error(job, ex)
      error do
        {
          level: "error",
          event: "enqueue",
          status: "error",
          job: job.class.name,
          queue: job.queue_name,
          exception: {
            class: ex.class.name,
            message: ex.message
          }
        }.to_json
      end
    end

    def enqueue_success(job, **extra)
      info do
        {
          level: "info",
          event: "enqueue",
          status: "success",
          job: job.class.name,
          job_id: job.job_id,
          queue: job.queue_name,
          arguments: args_info(job),
          **extra
        }.to_json
      end
    end
  end
end

ActiveJob::LogSubscriber.detach_from :active_job
ActiveJob::JsonLogSubscriber.attach_to :active_job
