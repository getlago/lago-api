# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ProviderTaxes::PullTaxesAndApplyJob do
  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, customer:) }
  let(:customer) { create(:customer, organization:) }

  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::ProviderTaxes::PullTaxesAndApplyService).to receive(:call)
      .with(invoice:)
      .and_return(result)
  end

  it "calls successfully the service" do
    described_class.perform_now(invoice:)

    expect(Invoices::ProviderTaxes::PullTaxesAndApplyService).to have_received(:call)
  end

  [
    [Customers::FailedToAcquireLock.new("customer-1"), 25],
    [BaseService::ThrottlingError.new, 25],
    [LagoHttpClient::HttpError.new(401, "body", "uri"), 6],
    [OpenSSL::SSL::SSLError.new("OpenSSL::SSL::SSLError"), 6],
    [Net::ReadTimeout.new("Net::ReadTimeout"), 6],
    [Net::OpenTimeout.new("Net::OpenTimeout"), 6],
  ].each do |error, attempts|
    error_class = error.class

    context "when a #{error_class} error is raised" do
      before do
        allow(Invoices::ProviderTaxes::PullTaxesAndApplyService).to receive(:call).and_raise(error)
      end

      it "raises a #{error_class.class.name} error and retries" do
        assert_performed_jobs(attempts, only: [described_class]) do
          expect do
            described_class.perform_later(invoice:)
          end.to raise_error(error_class)
        end
      end
    end
  end
end
