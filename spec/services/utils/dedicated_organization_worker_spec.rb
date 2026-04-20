# frozen_string_literal: true

require "rails_helper"

RSpec.describe Utils::DedicatedOrganizationWorker do
  around do |example|
    previous = ENV["LAGO_DEDICATED_WORKER_ORG_IDS"]
    example.run
  ensure
    ENV["LAGO_DEDICATED_WORKER_ORG_IDS"] = previous
  end

  describe ".organization_ids" do
    context "when env var is not set" do
      before { ENV.delete("LAGO_DEDICATED_WORKER_ORG_IDS") }

      it "returns an empty array" do
        expect(described_class.organization_ids).to eq([])
      end
    end

    context "when env var is blank" do
      before { ENV["LAGO_DEDICATED_WORKER_ORG_IDS"] = "" }

      it "returns an empty array" do
        expect(described_class.organization_ids).to eq([])
      end
    end

    context "when env var contains comma-separated values with whitespace" do
      before { ENV["LAGO_DEDICATED_WORKER_ORG_IDS"] = "  abc, def ,  , ghi " }

      it "parses and trims the values, dropping blanks" do
        expect(described_class.organization_ids).to eq(%w[abc def ghi])
      end
    end
  end

  describe ".enabled_for?" do
    before { ENV["LAGO_DEDICATED_WORKER_ORG_IDS"] = "org-1, org-2" }

    it "returns false for nil" do
      expect(described_class.enabled_for?(nil)).to be(false)
    end

    it "returns false for blank string" do
      expect(described_class.enabled_for?("")).to be(false)
    end

    it "returns true for a listed id" do
      expect(described_class.enabled_for?("org-1")).to be(true)
    end

    it "returns false for an unlisted id" do
      expect(described_class.enabled_for?("org-3")).to be(false)
    end
  end

  describe ".any?" do
    context "when env var is empty" do
      before { ENV.delete("LAGO_DEDICATED_WORKER_ORG_IDS") }

      it "returns false" do
        expect(described_class.any?).to be(false)
      end
    end

    context "when env var has ids" do
      before { ENV["LAGO_DEDICATED_WORKER_ORG_IDS"] = "org-1" }

      it "returns true" do
        expect(described_class.any?).to be(true)
      end
    end
  end
end
