# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Invoices::CreateJob do
  subject(:create_job) { described_class }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::Invoices::CreateService).to receive(:call).and_return(result)
  end

  it "calls the aggregator create invoice service" do
    described_class.perform_now(invoice:)

    expect(Integrations::Aggregator::Invoices::CreateService).to have_received(:call)
  end

  describe "Net::ReadTimeout retry" do
    before do
      allow(Integrations::Aggregator::Invoices::CreateService).to receive(:call).and_raise(Net::ReadTimeout.new)
    end

    context "when the invoice is for a NetSuite integration" do
      let(:integration) { create(:netsuite_integration, organization:) }

      before { create(:netsuite_customer, integration:, customer:) }

      it "schedules the next attempt at least 5 minutes later" do
        freeze_time do
          described_class.perform_now(invoice:)

          retry_at = ActiveJob::Base.queue_adapter.enqueued_jobs.last[:at]
          # NOTE: Tolerance covers ActiveJob's 15% retry jitter (up to ~45s on a 5-minute wait).
          expect(retry_at).to be_within(50.seconds).of(5.minutes.from_now.to_f)
        end
      end
    end

    context "when the invoice is for a non-NetSuite integration" do
      let(:integration) { create(:xero_integration, organization:) }

      before { create(:xero_customer, integration:, customer:) }

      it "schedules the next attempt with polynomial backoff" do
        freeze_time do
          described_class.perform_now(invoice:)

          retry_at = ActiveJob::Base.queue_adapter.enqueued_jobs.last[:at]
          # NOTE: First polynomial retry is ~3s (1**4 + 2) plus up to 15% jitter; well under a minute.
          expect(retry_at).to be < 1.minute.from_now.to_f
        end
      end
    end
  end
end
