# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lago::Meilisearch::Client do
  describe ".enabled?" do
    context "when LAGO_MEILISEARCH_URL is set" do
      around do |example|
        ENV["LAGO_MEILISEARCH_URL"] = "http://localhost:7700"
        example.run
        ENV.delete("LAGO_MEILISEARCH_URL")
      end

      it "returns true" do
        expect(described_class.enabled?).to be(true)
      end
    end

    context "when LAGO_MEILISEARCH_URL is not set" do
      around do |example|
        ENV.delete("LAGO_MEILISEARCH_URL")
        example.run
      end

      it "returns false" do
        expect(described_class.enabled?).to be(false)
      end
    end
  end

  describe ".search_enabled?" do
    around do |example|
      previous_url = ENV["LAGO_MEILISEARCH_URL"]
      previous_flag = ENV["LAGO_USE_MEILISEARCH"]
      example.run
      ENV["LAGO_MEILISEARCH_URL"] = previous_url
      ENV["LAGO_USE_MEILISEARCH"] = previous_flag
    end

    context "when configured and the flag is enabled" do
      before do
        ENV["LAGO_MEILISEARCH_URL"] = "http://localhost:7700"
        ENV["LAGO_USE_MEILISEARCH"] = "true"
      end

      it "returns true" do
        expect(described_class.search_enabled?).to be(true)
      end
    end

    context "when configured but the flag is disabled" do
      before do
        ENV["LAGO_MEILISEARCH_URL"] = "http://localhost:7700"
        ENV["LAGO_USE_MEILISEARCH"] = "false"
      end

      it "returns false" do
        expect(described_class.search_enabled?).to be(false)
      end
    end

    context "when the flag is enabled but Meilisearch is not configured" do
      before do
        ENV.delete("LAGO_MEILISEARCH_URL")
        ENV["LAGO_USE_MEILISEARCH"] = "true"
      end

      it "returns false" do
        expect(described_class.search_enabled?).to be(false)
      end
    end
  end
end
