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
  end

  context "with the maximum jitter" do
    let(:jitter) { 30 }

    it "retries 30 seconds after the window has passed" do
      handle

      expect(retry_at).to eq(90.seconds.from_now.to_f)
    end
  end

  context "when the error carries a retry delay" do
    let(:error) { BaseService::NextWindowThrottlingError.new(provider_name: :quickbooks, retry_after: 5.minutes) }

    it "retries after that delay" do
      handle

      expect(retry_at).to eq(5.minutes.from_now.to_f)
    end
  end

  context "when the error already occurred 30 times" do
    before { job.exception_executions = {"[BaseService::NextWindowThrottlingError]" => 30} }

    it "keeps retrying without an attempt cap" do
      expect(handle).to be_truthy
      expect(retry_at).to eq(60.seconds.from_now.to_f)
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
