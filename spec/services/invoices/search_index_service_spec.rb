# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::SearchIndexService do
  subject(:result) { described_class.call(invoice:) }

  let(:invoice) { create(:invoice) }

  before { allow(invoice).to receive(:ms_index!) }

  context "when Meilisearch is enabled" do
    before { allow(MeilisearchClient).to receive(:enabled?).and_return(true) }

    it "indexes the invoice" do
      result

      expect(invoice).to have_received(:ms_index!)
    end
  end

  context "when Meilisearch is disabled" do
    before { allow(MeilisearchClient).to receive(:enabled?).and_return(false) }

    it "does not index the invoice" do
      result

      expect(invoice).not_to have_received(:ms_index!)
    end
  end
end
