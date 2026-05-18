# frozen_string_literal: true

require "rails_helper"
require "active_job/json_log_subscriber"

class TestLogJob < ApplicationJob
  self.log_arguments = false

  def perform(*)
  end
end

class TestLogJobWithArgs < ApplicationJob
  self.log_arguments = true

  def perform(*)
  end
end

RSpec.describe ActiveJob::JsonLogSubscriber do
  subject(:subscriber) { described_class.new }

  let(:log_output) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log_output) }

  around do |example|
    original_logger = ActiveSupport::LogSubscriber.logger
    ActiveSupport::LogSubscriber.logger = logger
    example.run
  ensure
    ActiveSupport::LogSubscriber.logger = original_logger
  end

  def build_job(
    job_id: "test-job-id",
    queue_name: "default",
    enqueue_error: nil,
    enqueued_at: nil,
    scheduled_at: nil,
    executions: 0
  )
    TestLogJob.new.tap do |job|
      job.job_id = job_id
      job.queue_name = queue_name
      job.enqueue_error = enqueue_error
      job.enqueued_at = enqueued_at
      job.scheduled_at = scheduled_at
      job.executions = executions
    end
  end

  def build_event(name, payload)
    ActiveSupport::Notifications::Event.new(name, nil, nil, "transaction_id", payload)
  end

  def parsed_log_lines
    log_output.rewind
    log_output.read.lines.map { |l| JSON.parse(l) }
  end

  describe "#enqueue" do
    context "when the job is successfully enqueued" do
      it "logs a success entry with all expected attributes" do
        job = build_job(job_id: "abc-123", queue_name: "billing")
        event = build_event("enqueue.active_job", {job: job, exception_object: nil, aborted: false})

        subscriber.enqueue(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "enqueue",
          "status" => "success",
          "job" => "TestLogJob",
          "job_id" => "abc-123",
          "queue" => "billing",
          "arguments" => {}
        })
      end
    end

    context "when the job has an exception" do
      it "logs an error entry with all expected attributes" do
        exception = RuntimeError.new("redis down")
        job = build_job
        event = build_event("enqueue.active_job", {job: job, exception_object: exception})

        subscriber.enqueue(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "error",
          "event" => "enqueue",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "test-job-id",
          "queue" => "default",
          "arguments" => {},
          "exception" => {"class" => "RuntimeError", "message" => "redis down"}
        })
      end
    end

    context "when the job has an enqueue_error" do
      it "logs an error entry with all expected attributes" do
        error = ArgumentError.new("invalid args")
        job = build_job(queue_name: "low_priority", enqueue_error: error)
        event = build_event("enqueue.active_job", {job: job, exception_object: nil})

        subscriber.enqueue(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "error",
          "event" => "enqueue",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "test-job-id",
          "queue" => "low_priority",
          "arguments" => {},
          "exception" => {"class" => "ArgumentError", "message" => "invalid args"}
        })
      end
    end

    context "when the job is aborted" do
      it "logs an aborted entry with all expected attributes" do
        job = build_job
        event = build_event("enqueue.active_job", {job: job, exception_object: nil, aborted: true})

        subscriber.enqueue(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "enqueue",
          "status" => "aborted",
          "job" => "TestLogJob",
          "queue" => "default"
        })
      end
    end
  end

  describe "#enqueue_all" do
    context "when all jobs are successfully enqueued" do
      it "logs a success entry with all expected attributes for each job" do
        job1 = build_job(job_id: "id-1", queue_name: "low_priority")
        job2 = build_job(job_id: "id-2", queue_name: "default")
        event = build_event("enqueue_all.active_job", {jobs: [job1, job2], exception_object: nil})

        subscriber.enqueue_all(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(2)

        job1_log = logs.find { |l| l["job_id"] == "id-1" }
        job2_log = logs.find { |l| l["job_id"] == "id-2" }

        expect(job1_log).to eq({
          "level" => "info",
          "event" => "enqueue",
          "status" => "success",
          "job" => "TestLogJob",
          "job_id" => "id-1",
          "queue" => "low_priority",
          "arguments" => {}
        })

        expect(job2_log).to eq({
          "level" => "info",
          "event" => "enqueue",
          "status" => "success",
          "job" => "TestLogJob",
          "job_id" => "id-2",
          "queue" => "default",
          "arguments" => {}
        })
      end
    end

    context "when there is a global exception" do
      it "logs an error entry with all expected attributes for each job" do
        job1 = build_job(job_id: "id-1", queue_name: "billing")
        job2 = build_job(job_id: "id-2", queue_name: "default")
        exception = RuntimeError.new("connection failed")
        event = build_event("enqueue_all.active_job", {jobs: [job1, job2], exception_object: exception})

        subscriber.enqueue_all(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(2)

        job1_log = logs.find { |l| l["queue"] == "billing" }
        job2_log = logs.find { |l| l["queue"] == "default" }

        expected_exception = {"class" => "RuntimeError", "message" => "connection failed"}

        expect(job1_log).to eq({
          "level" => "error",
          "event" => "enqueue",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "id-1",
          "queue" => "billing",
          "arguments" => {},
          "exception" => expected_exception
        })

        expect(job2_log).to eq({
          "level" => "error",
          "event" => "enqueue",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "id-2",
          "queue" => "default",
          "arguments" => {},
          "exception" => expected_exception
        })
      end
    end

    context "when individual jobs have enqueue errors" do
      it "logs error for failed jobs and success for others with all expected attributes" do
        error = ArgumentError.new("queue full")
        failed_job = build_job(job_id: "id-fail", enqueue_error: error)
        successful_job = build_job(job_id: "id-ok", queue_name: "billing")
        event = build_event("enqueue_all.active_job", {jobs: [failed_job, successful_job], exception_object: nil})

        subscriber.enqueue_all(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(2)

        error_log = logs.find { |l| l["status"] == "error" }
        success_log = logs.find { |l| l["status"] == "success" }

        expect(error_log).to eq({
          "level" => "error",
          "event" => "enqueue",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "id-fail",
          "queue" => "default",
          "arguments" => {},
          "exception" => {"class" => "ArgumentError", "message" => "queue full"}
        })

        expect(success_log).to eq({
          "level" => "info",
          "event" => "enqueue",
          "status" => "success",
          "job" => "TestLogJob",
          "job_id" => "id-ok",
          "queue" => "billing",
          "arguments" => {}
        })
      end
    end

    context "when jobs have scheduled_at set" do
      it "includes enqueued_at in the log entry" do
        scheduled_at = Time.utc(2024, 6, 15, 10, 30, 0).to_f
        job = build_job(job_id: "id-1", scheduled_at: scheduled_at)
        event = build_event("enqueue_all.active_job", {jobs: [job], exception_object: nil})

        subscriber.enqueue_all(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "enqueue",
          "status" => "success",
          "job" => "TestLogJob",
          "job_id" => "id-1",
          "queue" => "default",
          "arguments" => {},
          "enqueued_at" => "2024-06-15T10:30:00.000Z"
        })
      end
    end

    context "when the global exception takes precedence over individual enqueue errors" do
      it "logs the global exception for all jobs" do
        individual_error = ArgumentError.new("individual error")
        global_error = RuntimeError.new("global failure")
        job = build_job(enqueue_error: individual_error)
        event = build_event("enqueue_all.active_job", {jobs: [job], exception_object: global_error})

        subscriber.enqueue_all(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "error",
          "event" => "enqueue",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "test-job-id",
          "queue" => "default",
          "arguments" => {},
          "exception" => {"class" => "RuntimeError", "message" => "global failure"}
        })
      end
    end
  end

  describe "#enqueue_at" do
    let(:scheduled_time) { Time.utc(2024, 6, 15, 10, 30, 0) }

    context "when the job is successfully enqueued" do
      it "logs a success entry with enqueued_at and all expected attributes" do
        job = build_job(job_id: "abc-123", queue_name: "billing", scheduled_at: scheduled_time.to_f)
        event = build_event("enqueue_at.active_job", {job: job, exception_object: nil, aborted: false})

        subscriber.enqueue_at(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "enqueue",
          "status" => "success",
          "job" => "TestLogJob",
          "job_id" => "abc-123",
          "queue" => "billing",
          "arguments" => {},
          "enqueued_at" => "2024-06-15T10:30:00.000Z"
        })
      end
    end

    context "when the job has an exception" do
      it "logs an error entry with all expected attributes" do
        exception = RuntimeError.new("redis down")
        job = build_job
        event = build_event("enqueue_at.active_job", {job: job, exception_object: exception})

        subscriber.enqueue_at(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "error",
          "event" => "enqueue",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "test-job-id",
          "queue" => "default",
          "arguments" => {},
          "exception" => {"class" => "RuntimeError", "message" => "redis down"}
        })
      end
    end

    context "when the job has an enqueue_error" do
      it "logs an error entry with all expected attributes" do
        error = ArgumentError.new("invalid args")
        job = build_job(queue_name: "low_priority", enqueue_error: error)
        event = build_event("enqueue_at.active_job", {job: job, exception_object: nil})

        subscriber.enqueue_at(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "error",
          "event" => "enqueue",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "test-job-id",
          "queue" => "low_priority",
          "arguments" => {},
          "exception" => {"class" => "ArgumentError", "message" => "invalid args"}
        })
      end
    end

    context "when the job is aborted" do
      it "logs an aborted entry with all expected attributes" do
        job = build_job
        event = build_event("enqueue_at.active_job", {job: job, exception_object: nil, aborted: true})

        subscriber.enqueue_at(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "enqueue",
          "status" => "aborted",
          "job" => "TestLogJob",
          "queue" => "default"
        })
      end
    end
  end

  describe "#perform_start" do
    context "when the job has no enqueued_at" do
      it "logs a start entry without enqueued_at" do
        job = build_job(job_id: "abc-123", queue_name: "billing")
        event = build_event("perform_start.active_job", {job: job})

        subscriber.perform_start(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "perform",
          "status" => "start",
          "job" => "TestLogJob",
          "job_id" => "abc-123",
          "arguments" => {},
          "queue" => "billing"
        })
      end
    end

    context "when the job has an enqueued_at" do
      it "logs a start entry with enqueued_at" do
        enqueued_at = Time.utc(2024, 6, 15, 10, 30, 0)
        job = build_job(job_id: "abc-123", queue_name: "billing", enqueued_at: enqueued_at)
        event = build_event("perform_start.active_job", {job: job})

        subscriber.perform_start(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "perform",
          "status" => "start",
          "job" => "TestLogJob",
          "job_id" => "abc-123",
          "arguments" => {},
          "queue" => "billing",
          "enqueued_at" => "2024-06-15T10:30:00.000Z"
        })
      end
    end
  end

  describe "#perform" do
    context "when the job completes successfully" do
      it "logs a success entry with all expected attributes" do
        job = build_job(job_id: "abc-123", queue_name: "billing")
        event = build_event("perform.active_job", {job: job, exception_object: nil, aborted: false})
        allow(event).to receive(:duration).and_return(123.456)

        subscriber.perform(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "perform",
          "status" => "success",
          "job" => "TestLogJob",
          "duration" => 123.46,
          "job_id" => "abc-123",
          "queue" => "billing"
        })
      end
    end

    context "when the job raises an exception" do
      it "logs an error entry with all expected attributes" do
        exception = RuntimeError.new("something broke")
        job = build_job(job_id: "abc-123", executions: 2)
        event = build_event("perform.active_job", {job: job, exception_object: exception})
        allow(event).to receive(:duration).and_return(45.678)

        subscriber.perform(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "error",
          "event" => "perform",
          "status" => "error",
          "job" => "TestLogJob",
          "duration" => 45.68,
          "job_id" => "abc-123",
          "queue" => "default",
          "arguments" => {},
          "attempt_count" => 2,
          "exception" => {"class" => "RuntimeError", "message" => "something broke"}
        })
      end

      context "when the exception has a backtrace" do
        it "truncates the backtrace to the first 10 frames" do
          exception = RuntimeError.new("boom")
          exception.set_backtrace((1..20).map { |i| "frame_#{i}" })
          job = build_job(job_id: "abc-123")
          event = build_event("perform.active_job", {job: job, exception_object: exception})
          allow(event).to receive(:duration).and_return(1.0)

          subscriber.perform(event)

          logs = parsed_log_lines
          expect(logs.first["exception"]["backtrace"]).to eq((1..10).map { |i| "frame_#{i}" })
        end
      end

      context "when the exception has an empty backtrace" do
        it "omits the backtrace key" do
          exception = RuntimeError.new("boom")
          exception.set_backtrace([])
          job = build_job(job_id: "abc-123")
          event = build_event("perform.active_job", {job: job, exception_object: exception})
          allow(event).to receive(:duration).and_return(1.0)

          subscriber.perform(event)

          logs = parsed_log_lines
          expect(logs.first["exception"]).not_to have_key("backtrace")
        end
      end

      context "when the exception has a nil backtrace" do
        it "omits the backtrace key" do
          exception = RuntimeError.new("boom")
          job = build_job(job_id: "abc-123")
          event = build_event("perform.active_job", {job: job, exception_object: exception})
          allow(event).to receive(:duration).and_return(1.0)

          subscriber.perform(event)

          logs = parsed_log_lines
          expect(logs.first["exception"]).not_to have_key("backtrace")
        end
      end

      context "when the job arguments contain an organization_id" do
        it "includes the organization_id in the log entry" do
          exception = RuntimeError.new("boom")
          job = TestLogJobWithArgs.new(organization_id: "org-42")
          job.job_id = "abc-123"
          job.queue_name = "default"
          job.executions = 1
          event = build_event("perform.active_job", {job: job, exception_object: exception})
          allow(event).to receive(:duration).and_return(1.0)

          subscriber.perform(event)

          logs = parsed_log_lines
          expect(logs.first["organization_id"]).to eq("org-42")
        end
      end

      context "when no argument carries an organization_id" do
        it "omits the organization_id key" do
          exception = RuntimeError.new("boom")
          job = build_job(job_id: "abc-123")
          event = build_event("perform.active_job", {job: job, exception_object: exception})
          allow(event).to receive(:duration).and_return(1.0)

          subscriber.perform(event)

          logs = parsed_log_lines
          expect(logs.first).not_to have_key("organization_id")
        end
      end

      context "when arguments string exceeds the maximum length" do
        it "truncates the arguments string with a suffix" do
          exception = RuntimeError.new("boom")
          long_arg = "a" * 2000
          job = TestLogJobWithArgs.new(long_arg)
          job.job_id = "abc-123"
          job.queue_name = "default"
          job.executions = 1
          event = build_event("perform.active_job", {job: job, exception_object: exception})
          allow(event).to receive(:duration).and_return(1.0)

          subscriber.perform(event)

          logs = parsed_log_lines
          arguments = logs.first["arguments"]
          expect(arguments.length).to eq(1000 + "… (truncated)".length)
          expect(arguments).to end_with("… (truncated)")
        end
      end
    end

    context "when the job is aborted" do
      it "logs an aborted entry with all expected attributes" do
        job = build_job(job_id: "abc-123")
        event = build_event("perform.active_job", {job: job, exception_object: nil, aborted: true})
        allow(event).to receive(:duration).and_return(0.12)

        subscriber.perform(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "perform",
          "status" => "aborted",
          "job" => "TestLogJob",
          "duration" => 0.12,
          "job_id" => "abc-123",
          "queue" => "default"
        })
      end
    end
  end

  describe "#enqueue_retry" do
    context "when there is an error" do
      it "logs a retry error entry with all expected attributes" do
        exception = RuntimeError.new("transient failure")
        job = build_job(job_id: "abc-123", executions: 3)
        event = build_event("enqueue_retry.active_job", {job: job, error: exception, wait: 30.5})

        subscriber.enqueue_retry(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "error",
          "event" => "retry",
          "status" => "error",
          "job" => "TestLogJob",
          "job_id" => "abc-123",
          "execution" => 3,
          "wait" => 30,
          "exception" => {"class" => "RuntimeError", "message" => "transient failure"}
        })
      end
    end

    context "when there is no error" do
      it "logs a retry success entry with all expected attributes" do
        job = build_job(job_id: "abc-123", executions: 1)
        event = build_event("enqueue_retry.active_job", {job: job, error: nil, wait: 5})

        subscriber.enqueue_retry(event)

        logs = parsed_log_lines
        expect(logs.size).to eq(1)
        expect(logs.first).to eq({
          "level" => "info",
          "event" => "retry",
          "status" => "success",
          "job" => "TestLogJob",
          "job_id" => "abc-123",
          "execution" => 1,
          "wait" => 5
        })
      end
    end
  end

  describe "#retry_stopped" do
    it "logs a stopped entry with all expected attributes" do
      exception = RuntimeError.new("permanent failure")
      job = build_job(job_id: "abc-123", executions: 5)
      event = build_event("retry_stopped.active_job", {job: job, error: exception})

      subscriber.retry_stopped(event)

      logs = parsed_log_lines
      expect(logs.size).to eq(1)
      expect(logs.first).to eq({
        "level" => "error",
        "event" => "retry",
        "status" => "stopped",
        "job" => "TestLogJob",
        "job_id" => "abc-123",
        "queue" => "default",
        "arguments" => {},
        "attempt_count" => 5,
        "exception" => {"class" => "RuntimeError", "message" => "permanent failure"}
      })
    end

    context "when the job arguments contain an organization_id" do
      it "includes the organization_id in the log entry" do
        exception = RuntimeError.new("permanent failure")
        job = TestLogJobWithArgs.new(organization_id: "org-77")
        job.job_id = "abc-123"
        job.queue_name = "default"
        job.executions = 5
        event = build_event("retry_stopped.active_job", {job: job, error: exception})

        subscriber.retry_stopped(event)

        logs = parsed_log_lines
        expect(logs.first["organization_id"]).to eq("org-77")
      end
    end
  end

  describe "#discard" do
    it "logs a discard entry with all expected attributes" do
      exception = RuntimeError.new("unrecoverable error")
      job = build_job(job_id: "abc-123", executions: 2)
      event = build_event("discard.active_job", {job: job, error: exception})

      subscriber.discard(event)

      logs = parsed_log_lines
      expect(logs.size).to eq(1)
      expect(logs.first).to eq({
        "level" => "error",
        "event" => "discard",
        "status" => "error",
        "job" => "TestLogJob",
        "job_id" => "abc-123",
        "queue" => "default",
        "arguments" => {},
        "attempt_count" => 2,
        "exception" => {"class" => "RuntimeError", "message" => "unrecoverable error"}
      })
    end

    context "when the job arguments contain an organization_id" do
      it "includes the organization_id in the log entry" do
        exception = RuntimeError.new("unrecoverable")
        job = TestLogJobWithArgs.new(organization_id: "org-99")
        job.job_id = "abc-123"
        job.queue_name = "default"
        job.executions = 1
        event = build_event("discard.active_job", {job: job, error: exception})

        subscriber.discard(event)

        logs = parsed_log_lines
        expect(logs.first["organization_id"]).to eq("org-99")
      end
    end
  end

  describe "organization_id extraction" do
    let(:exception) { RuntimeError.new("boom") }

    def perform_event(job)
      event = build_event("perform.active_job", {job: job, exception_object: exception})
      allow(event).to receive(:duration).and_return(1.0)
      event
    end

    context "when an argument is a hash with a symbol :organization_id key" do
      it "extracts the organization_id" do
        job = TestLogJobWithArgs.new(organization_id: "org-symbol")
        job.job_id = "abc"
        job.queue_name = "default"
        job.executions = 1

        subscriber.perform(perform_event(job))

        expect(parsed_log_lines.first["organization_id"]).to eq("org-symbol")
      end
    end

    context "when an argument is a hash with a string 'organization_id' key" do
      it "extracts the organization_id" do
        job = TestLogJobWithArgs.new({"organization_id" => "org-string"})
        job.job_id = "abc"
        job.queue_name = "default"
        job.executions = 1

        subscriber.perform(perform_event(job))

        expect(parsed_log_lines.first["organization_id"]).to eq("org-string")
      end
    end

    context "when an argument responds to organization_id" do
      it "extracts the organization_id" do
        org_carrier = Struct.new(:organization_id).new("org-from-method")
        job = TestLogJobWithArgs.new(org_carrier)
        job.job_id = "abc"
        job.queue_name = "default"
        job.executions = 1

        subscriber.perform(perform_event(job))

        expect(parsed_log_lines.first["organization_id"]).to eq("org-from-method")
      end
    end

    context "when no argument carries an organization_id" do
      it "omits the organization_id key" do
        job = TestLogJobWithArgs.new("plain-string", 42)
        job.job_id = "abc"
        job.queue_name = "default"
        job.executions = 1

        subscriber.perform(perform_event(job))

        expect(parsed_log_lines.first).not_to have_key("organization_id")
      end
    end
  end
end
