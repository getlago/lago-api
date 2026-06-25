# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RemoveFromSearchIndexService do
  subject(:result) { described_class.call(invoice_id:) }

  let(:invoice_id) { SecureRandom.uuid }
  let(:index) { instance_double(Meilisearch::Index, delete_document: true) }

  before do
    allow(MeilisearchClient).to receive(:invoices_index).and_return(index)
  end

  context "when Meilisearch is enabled" do
    before { allow(MeilisearchClient).to receive(:enabled?).and_return(true) }

    it "deletes the document from the index" do
      result

      expect(index).to have_received(:delete_document).with(invoice_id)
    end
  end

  context "when Meilisearch is disabled" do
    before { allow(MeilisearchClient).to receive(:enabled?).and_return(false) }

    it "does not call the index" do
      result

      expect(index).not_to have_received(:delete_document)
    end
  end
end
