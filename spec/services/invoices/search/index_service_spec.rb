# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Search::IndexService do
  subject(:result) { described_class.call(invoice:) }

  let(:invoice) { create(:invoice) }

  before { allow(invoice).to receive(:ms_index!) }

  context "when Meilisearch is enabled" do
    before { stub_const("ENV", ENV.to_h.merge("LAGO_MEILISEARCH_URL" => "http://meilisearch:7700")) }

    it "indexes the invoice" do
      result

      expect(invoice).to have_received(:ms_index!)
    end
  end

  context "when Meilisearch is disabled" do
    it "does not index the invoice" do
      result

      expect(invoice).not_to have_received(:ms_index!)
    end
  end
end
