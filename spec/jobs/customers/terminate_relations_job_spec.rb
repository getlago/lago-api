# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::TerminateRelationsJob do
  let(:customer) { create(:customer, :deleted) }

  it "calls the service" do
    allow(Customers::TerminateRelationsService)
      .to receive(:call)
      .with(customer:)
      .and_return(Customers::TerminateRelationsService::Result.new)

    described_class.perform_now(customer_id: customer.id)

    expect(Customers::TerminateRelationsService)
      .to have_received(:call)
  end

  context "when the customer belongs to the shadow organization of a migration" do
    let(:contract) { create(:contract, :pending, customer:) }
    let(:invoice) { create(:invoice, :draft, customer:) }

    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization)
      contract
      invoice
    end

    it "cancels the contract and deletes the draft" do
      described_class.perform_now(customer_id: customer.id)

      expect(contract.reload).to be_canceled
      expect(invoice.reload).to be_deleted
    end
  end
end
