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
  end

  it "runs on the meilisearch queue" do
    expect(described_class.new.queue_name).to eq("meilisearch")
  end

  it "enqueues a reindex job for each of the customer's invoices" do
    expect { perform }
      .to have_enqueued_job(Invoices::SearchIndexJob).with(invoice.id)
      .and not_have_enqueued_job(Invoices::SearchIndexJob).with(other_invoice.id)
  end

  context "when the customer is discarded" do
    before { customer.discard! }

    it "still reindexes its invoices" do
      expect { perform }.to have_enqueued_job(Invoices::SearchIndexJob).with(invoice.id)
    end
  end

  context "when the customer does not exist" do
    subject(:perform) { described_class.perform_now(SecureRandom.uuid) }

    it "does nothing" do
      expect { perform }.not_to have_enqueued_job(Invoices::SearchIndexJob)
    end
  end
end
