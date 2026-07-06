# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Search::RemoveFromIndexService do
  subject(:result) { described_class.call(invoice_id:) }

  let(:invoice_id) { SecureRandom.uuid }
  let(:index) { instance_double(Meilisearch::Index, delete_document: true) }

  before { allow(Invoice).to receive(:index).and_return(index) }

  context "when Meilisearch is enabled" do
    before { stub_const("ENV", ENV.to_h.merge("LAGO_MEILISEARCH_URL" => "http://meilisearch:7700")) }

    it "deletes the document from the index" do
      result

      expect(index).to have_received(:delete_document).with(invoice_id)
    end
  end

  context "when Meilisearch is disabled" do
    it "does not touch the index" do
      result

      expect(index).not_to have_received(:delete_document)
    end
  end
end
