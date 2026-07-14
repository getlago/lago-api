# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lago::Meilisearch do
  describe ".indexing_enabled?" do
    context "when LAGO_MEILISEARCH_URL is set" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_MEILISEARCH_URL" => "http://localhost:7700")) }

      it "returns true" do
        expect(described_class.indexing_enabled?).to be(true)
      end
    end

    context "when LAGO_MEILISEARCH_URL is not set" do
      it "returns false" do
        expect(described_class.indexing_enabled?).to be(false)
      end
    end
  end

  describe ".search_enabled?" do
    context "when configured and the flag is enabled" do
      before do
        stub_const(
          "ENV",
          ENV.to_h.merge("LAGO_MEILISEARCH_URL" => "http://localhost:7700", "LAGO_MEILISEARCH_SEARCH_ENABLED" => "true")
        )
      end

      it "returns true" do
        expect(described_class.search_enabled?).to be(true)
      end
    end

    context "when configured but the flag is disabled" do
      before do
        stub_const(
          "ENV",
          ENV.to_h.merge("LAGO_MEILISEARCH_URL" => "http://localhost:7700", "LAGO_MEILISEARCH_SEARCH_ENABLED" => "false")
        )
      end

      it "returns false" do
        expect(described_class.search_enabled?).to be(false)
      end
    end

    context "when the flag is enabled but Meilisearch is not configured" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_MEILISEARCH_SEARCH_ENABLED" => "true")) }

      it "returns false" do
        expect(described_class.search_enabled?).to be(false)
      end
    end
  end
end
