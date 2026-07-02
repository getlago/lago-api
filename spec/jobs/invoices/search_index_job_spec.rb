# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::SearchIndexJob do
  subject(:perform) { described_class.perform_now(invoice_id) }

  let(:invoice) { create(:invoice) }

  before do
    allow(Invoices::Search::IndexService).to receive(:call!)
    allow(Invoices::Search::RemoveFromIndexService).to receive(:call!)
  end

  it "runs on the meilisearch queue" do
    expect(described_class.new.queue_name).to eq("meilisearch")
  end

  context "when the invoice exists" do
    let(:invoice_id) { invoice.id }

    it "indexes the invoice" do
      perform

      expect(Invoices::Search::IndexService).to have_received(:call!).with(invoice:)
    end
  end

  context "when the invoice does not exist" do
    let(:invoice_id) { SecureRandom.uuid }

    it "removes the invoice from the index" do
      perform

      expect(Invoices::Search::RemoveFromIndexService).to have_received(:call!).with(invoice_id:)
    end
  end
end
