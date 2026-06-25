# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::SearchIndexService do
  subject(:result) { described_class.call(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) do
    create(
      :customer,
      organization:,
      name: "Acme Corp",
      firstname: "John",
      lastname: "Doe",
      legal_name: "Acme Corporation",
      external_id: "ext-123",
      email: "john@acme.test"
    )
  end
  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      number: "INV-001",
      status: "finalized",
      payment_status: "pending",
      total_amount_cents: 1000,
      total_paid_amount_cents: 400,
      issuing_date: Date.new(2026, 1, 15)
    )
  end
  let(:index) { instance_double(Meilisearch::Index, add_documents: true) }

  before do
    allow(MeilisearchClient).to receive(:enabled?).and_return(true)
    allow(MeilisearchClient).to receive(:invoices_index).and_return(index)
  end

  it "upserts the invoice document into the index" do
    result

    expect(index).to have_received(:add_documents) do |documents, primary_key|
      expect(primary_key).to eq("id")

      document = documents.first
      expect(document).to include(
        id: invoice.id,
        organization_id: organization.id,
        customer_id: customer.id,
        number: "INV-001",
        status: "finalized",
        payment_status: "pending",
        total_amount_cents: 1000,
        due_amount_cents: 600,
        partially_paid: true,
        customer_name: "Acme Corp",
        customer_external_id: "ext-123",
        customer_email: "john@acme.test"
      )
      expect(document[:issuing_date]).to eq(Date.new(2026, 1, 15).to_time(:utc).to_i)
    end
  end

  context "with metadata, subscriptions and settlements" do
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:billing_entity) { organization.default_billing_entity }

    before do
      create(:invoice_metadata, invoice:, key: "po", value: "123")
      create(:invoice_subscription, invoice:, subscription:)
      create(:invoice_settlement, :with_payment, organization:, billing_entity:, target_invoice: invoice)
    end

    it "denormalizes the associated values" do
      result

      expect(index).to have_received(:add_documents) do |documents, _|
        document = documents.first
        expect(document[:metadata]).to eq(["po::123"])
        expect(document[:metadata_keys]).to eq(["po"])
        expect(document[:subscription_ids]).to eq([subscription.id])
        expect(document[:settlement_types]).to eq(["payment"])
      end
    end
  end

  context "when Meilisearch is disabled" do
    before { allow(MeilisearchClient).to receive(:enabled?).and_return(false) }

    it "does not call the index" do
      result

      expect(index).not_to have_received(:add_documents)
    end
  end
end
