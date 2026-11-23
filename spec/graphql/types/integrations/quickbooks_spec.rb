# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Integrations::Quickbooks do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")

    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:connection_id).of_type("ID!")
    expect(subject).to have_field(:has_mappings_configured).of_type("Boolean")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:realm_id).of_type("String")
    expect(subject).to have_field(:sandbox).of_type("Boolean!")

    expect(subject).to have_field(:sync_credit_notes).of_type("Boolean")
    expect(subject).to have_field(:sync_invoices).of_type("Boolean")
    expect(subject).to have_field(:sync_payments).of_type("Boolean")
  end

  it "exposes no other field" do
    expect(subject.fields.keys).to contain_exactly(
      "code", "connectionId", "hasMappingsConfigured", "id", "name", "realmId", "sandbox",
      "syncCreditNotes", "syncInvoices", "syncPayments"
    )
  end

  describe "#has_mappings_configured" do
    subject(:has_mappings_configured) { described_class.authorized_new(integration, context).has_mappings_configured }

    let(:context) { GraphQL::Query.new(LagoApiSchema, "{ __typename }").context }
    let(:integration) { create(:quickbooks_integration) }

    context "without a collection mapping" do
      it { is_expected.to be(false) }
    end

    context "with a collection mapping of another type" do
      before { create(:xero_collection_mapping, integration:) }

      it { is_expected.to be(false) }
    end

    context "with a QuickBooks collection mapping" do
      before { create(:quickbooks_collection_mapping, integration:) }

      it { is_expected.to be(true) }
    end
  end
end
