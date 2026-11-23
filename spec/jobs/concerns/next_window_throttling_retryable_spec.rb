# frozen_string_literal: true

require "rails_helper"

RSpec.describe NextWindowThrottlingRetryable do
  subject(:handle) { job.rescue_with_handler(error) }

  let(:job_class) do
    Class.new(ApplicationJob) do
      include NextWindowThrottlingRetryable

      def perform
      end
    end
  end
  let(:job) { job_class.new }
  let(:error) { BaseService::NextWindowThrottlingError.new(provider_name: :quickbooks) }
  let(:jitter) { 0 }
  let(:retry_at) { ActiveJob::Base.queue_adapter.enqueued_jobs.last[:at] }

  around { |example| freeze_time { example.run } }

  before do
    stub_const("NextWindowThrottlingRetryableTestJob", job_class)
    allow(job).to receive(:rand).with(0..30).and_return(jitter)
  end

  it "retries once the rate limit window has passed, with a jitter of 0 to 30 seconds" do
    handle

    expect(retry_at).to eq(60.seconds.from_now.to_f)
    expect(job).to have_received(:rand).with(0..30)
    expect(job.exception_executions).to eq("[BaseService::NextWindowThrottlingError]" => 1)
  end

  context "with the maximum jitter" do
    let(:jitter) { 30 }

    it "retries 30 seconds after the window has passed" do
      handle

      expect(retry_at).to eq(90.seconds.from_now.to_f)
    end
  end

  context "when the error carries the time left in the window" do
    let(:error) { BaseService::NextWindowThrottlingError.new(provider_name: :quickbooks, retry_after: 15.seconds) }

    it "retries when that window ends" do
      handle

      expect(retry_at).to eq(15.seconds.from_now.to_f)
    end
  end

  context "when the job was already throttled 4 times" do
    before { job.exception_executions = {"[BaseService::NextWindowThrottlingError]" => 4} }

    it "waits one more window per earlier retry" do
      handle

      expect(retry_at).to eq(300.seconds.from_now.to_f)
    end
  end

  context "when the job was already throttled 20 times" do
    before { job.exception_executions = {"[BaseService::NextWindowThrottlingError]" => 20} }

    it "waits 10 minutes at most" do
      handle

      expect(retry_at).to eq(600.seconds.from_now.to_f)
    end
  end

  context "when the job was already throttled 39 times" do
    before { job.exception_executions = {"[BaseService::NextWindowThrottlingError]" => 39} }

    it "stops retrying and raises the error" do
      expect { handle }.to raise_error(BaseService::NextWindowThrottlingError)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end
  end

  context "when the job is throttled on every run" do
    let(:job_class) do
      Class.new(ApplicationJob) do
        include NextWindowThrottlingRetryable

        def perform
          raise BaseService::NextWindowThrottlingError.new(provider_name: :quickbooks)
        end
      end
    end

    def run_enqueued
      perform_enqueued_jobs(only: job_class, at: 15.minutes.from_now)
    end

    it "re-enqueues the job until the bound, then raises and leaves nothing enqueued" do
      job_class.perform_later

      (NextWindowThrottlingRetryable::NEXT_WINDOW_MAX_ATTEMPTS - 1).times { run_enqueued }

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == job_class }
      expect(enqueued.size).to eq(1)
      expect(enqueued.first["exception_executions"]).to eq("[BaseService::NextWindowThrottlingError]" => 39)

      expect { run_enqueued }.to raise_error(BaseService::NextWindowThrottlingError)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == job_class }).to be_empty
    end
  end

  context "with the regular throttling error" do
    let(:error) { BaseService::ThrottlingError.new(provider_name: :xero) }

    it "does not handle it" do
      expect(handle).to be_nil
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end
  end
end
