# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ProviderTaxes::VoidJob do
  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, customer:) }
  let(:customer) { create(:customer, organization:) }

  let(:result) { Invoices::ProviderTaxes::VoidService::Result.new }

  before do
    allow(Invoices::ProviderTaxes::VoidService).to receive(:call)
      .with(invoice:)
      .and_return(result)
  end

  context "when there is anrok customer" do
    let(:integration) { create(:anrok_integration, organization:) }
    let(:integration_customer) { create(:anrok_customer, integration:, customer:) }

    before { integration_customer }

    it "calls successfully void service" do
      described_class.perform_now(invoice:)

      expect(Invoices::ProviderTaxes::VoidService).to have_received(:call)
    end
  end

  context "when there is avalara customer" do
    let(:integration) { create(:avalara_integration, organization:) }
    let(:integration_customer) { create(:avalara_customer, integration:, customer:) }

    before { integration_customer }

    it "calls successfully void service" do
      described_class.perform_now(invoice:)

      expect(Invoices::ProviderTaxes::VoidService).to have_received(:call)
    end
  end

  context "when there is NOT tax customer" do
    it "does not call void service" do
      described_class.perform_now(invoice:)

      expect(Invoices::ProviderTaxes::VoidService).not_to have_received(:call)
    end
  end

  describe "retry_on" do
    let(:integration) { create(:anrok_integration, organization:) }
    let(:integration_customer) { create(:anrok_customer, integration:, customer:) }

    before { integration_customer }

    [
      Integrations::Aggregator::BadGatewayError.new("body", "uri"),
      Integrations::Aggregator::RequestLimitError.new(LagoHttpClient::HttpError.new(429, "limit", "uri")),
      Integrations::Aggregator::OutOfMemoryError.new,
      Integrations::Aggregator::TaskInProgressError.new,
      Integrations::Aggregator::TaskExpiredError.new,
      Integrations::Aggregator::OrchestratorFailureError.new,
      Integrations::Aggregator::ServerContentionError.new,
      Integrations::Aggregator::TimeoutError.new
    ].each do |error|
      error_class = error.class

      context "when a #{error_class} error is raised" do
        before do
          allow(Invoices::ProviderTaxes::VoidService).to receive(:call).and_raise(error)
        end

        it "raises a #{error_class.name} error and retries" do
          assert_performed_jobs(6, only: [described_class]) do
            expect do
              described_class.perform_later(invoice:)
            end.to raise_error(error_class)
          end
        end
      end
    end
  end
end
