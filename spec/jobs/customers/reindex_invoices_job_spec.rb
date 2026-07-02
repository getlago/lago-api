# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::ReindexInvoicesJob do
  subject(:perform) { described_class.perform_now(customer.id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:other_invoice) { create(:invoice, organization:) }

  before do
    invoice
    other_invoice
    allow(Invoices::SearchIndexJob).to receive(:perform_later)
  end

  it "runs on the meilisearch queue" do
    expect(described_class.new.queue_name).to eq("meilisearch")
  end

  it "enqueues a reindex job for each of the customer's invoices" do
    perform

    expect(Invoices::SearchIndexJob).to have_received(:perform_later).with(invoice.id)
    expect(Invoices::SearchIndexJob).not_to have_received(:perform_later).with(other_invoice.id)
  end

  context "when the customer is discarded" do
    before { customer.discard! }

    it "still reindexes its invoices" do
      perform

      expect(Invoices::SearchIndexJob).to have_received(:perform_later).with(invoice.id)
    end
  end

  context "when the customer does not exist" do
    subject(:perform) { described_class.perform_now(SecureRandom.uuid) }

    it "does nothing" do
      perform

      expect(Invoices::SearchIndexJob).not_to have_received(:perform_later)
    end
  end
end
