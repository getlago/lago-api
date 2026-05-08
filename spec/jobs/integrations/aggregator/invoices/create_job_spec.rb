# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Invoices::CreateJob do
  subject(:create_job) { described_class }

  let(:invoice) { create(:invoice) }
  let(:result) { BaseService::Result.new }
  let(:find_result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::Invoices::CreateService).to receive(:call).and_return(result)
    allow(Integrations::Aggregator::Invoices::FindService).to receive(:call).and_return(find_result)
  end

  context "when it is the first execution" do
    it "calls CreateService without calling FindService" do
      described_class.perform_now(invoice:)

      expect(Integrations::Aggregator::Invoices::FindService).not_to have_received(:call)
      expect(Integrations::Aggregator::Invoices::CreateService).to have_received(:call).with(invoice:)
    end
  end

  context "when it is a retry execution" do
    subject(:create_job) { described_class.new(invoice:) }

    before { create_job.executions = 1 }

    context "when FindService does not find the invoice upstream" do
      it "calls FindService and then CreateService" do
        create_job.perform_now

        expect(Integrations::Aggregator::Invoices::FindService).to have_received(:call).with(invoice:)
        expect(Integrations::Aggregator::Invoices::CreateService).to have_received(:call).with(invoice:)
      end
    end

    context "when FindService finds the invoice upstream" do
      before { find_result.external_id = "12345" }

      it "skips CreateService" do
        create_job.perform_now

        expect(Integrations::Aggregator::Invoices::FindService).to have_received(:call).with(invoice:)
        expect(Integrations::Aggregator::Invoices::CreateService).not_to have_received(:call)
      end
    end

    context "when FindService fails with a retryable HTTP error" do
      let(:http_error) { LagoHttpClient::HttpError.new(500, "{}", nil) }

      before do
        allow(find_result).to receive(:raise_if_error!).and_raise(http_error)
      end

      it "re-enqueues the job and does not call CreateService" do
        expect { create_job.perform_now }
          .to have_enqueued_job(described_class)
        expect(Integrations::Aggregator::Invoices::CreateService).not_to have_received(:call)
      end
    end

    context "when FindService fails with a non-retryable failure" do
      before { find_result.non_retryable_failure!(code: "client_error", message: "bad request") }

      it "discards the job and does not call CreateService" do
        expect { create_job.perform_now }.not_to raise_error
        expect(Integrations::Aggregator::Invoices::CreateService).not_to have_received(:call)
      end
    end
  end
end
