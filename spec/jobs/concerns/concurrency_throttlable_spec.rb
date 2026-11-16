# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConcurrencyThrottlable do
  let(:job_class) do
    Class.new(ApplicationJob) do
      include ConcurrencyThrottlable

      def perform
      end
    end
  end

  before { stub_const("ConcurrencyThrottlableTestJob", job_class) }

  describe "next window throttling retry" do
    let(:error) { BaseService::NextWindowThrottlingError.new(provider_name: :quickbooks) }

    def retry_at
      ActiveJob::Base.queue_adapter.enqueued_jobs.last[:at]
    end

    it "retries once the rate limit window has passed, with up to 30 seconds of jitter" do
      freeze_time do
        job_class.new.rescue_with_handler(error)

        expect(retry_at).to be_between(60.seconds.from_now.to_f, 90.seconds.from_now.to_f)
      end
    end

    it "uses the retry delay carried by the error" do
      error = BaseService::NextWindowThrottlingError.new(provider_name: :quickbooks, retry_after: 5.minutes)

      freeze_time do
        job_class.new.rescue_with_handler(error)

        expect(retry_at).to be_between(5.minutes.from_now.to_f, (5.minutes + 30.seconds).from_now.to_f)
      end
    end

    it "keeps retrying without an attempt cap" do
      job = job_class.new
      job.executions = 30

      freeze_time do
        expect(job.rescue_with_handler(error)).to be_truthy
        expect(retry_at).to be_between(60.seconds.from_now.to_f, 90.seconds.from_now.to_f)
      end
    end

    it "does not handle the regular throttling error" do
      error = BaseService::ThrottlingError.new(provider_name: :xero)

      expect(job_class.new.rescue_with_handler(error)).to be_nil
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end
  end

  # NOTE: ActiveSupport::Rescuable picks the most recently declared handler matching the error class.
  def handled_error_class(job_class, error)
    job_class.rescue_handlers.rfind { |class_name, _| error.is_a?(class_name.constantize) }&.first
  end

  [
    IntegrationCustomers::CreateJob,
    IntegrationCustomers::UpdateJob,
    Integrations::Aggregator::Invoices::CreateJob,
    Integrations::Aggregator::CreditNotes::CreateJob,
    Integrations::Aggregator::Payments::CreateJob
  ].each do |integration_job_class|
    describe integration_job_class do
      it "handles the next window throttling error with the next window retry" do
        error = BaseService::NextWindowThrottlingError.new(provider_name: :quickbooks)

        expect(handled_error_class(integration_job_class, error)).to eq("BaseService::NextWindowThrottlingError")
      end

      it "keeps its own retry rule for the regular throttling error" do
        error = BaseService::ThrottlingError.new(provider_name: :xero)

        expect(handled_error_class(integration_job_class, error)).to eq("BaseService::ThrottlingError")
      end
    end
  end
end
