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
end
