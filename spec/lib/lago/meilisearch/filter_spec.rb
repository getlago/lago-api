# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lago::Meilisearch::Filter do
  describe ".eq" do
    it "quotes string values" do
      expect(described_class.eq("currency", "EUR")).to eq(%(currency = "EUR"))
    end

    it "renders booleans bare" do
      expect(described_class.eq("self_billed", true)).to eq("self_billed = true")
    end

    it "renders numerics bare" do
      expect(described_class.eq("version", 3)).to eq("version = 3")
    end

    it "escapes embedded quotes" do
      expect(described_class.eq("customer_name", %(Acme "Inc"))).to eq(%(customer_name = "Acme \\"Inc\\""))
    end

    it "escapes backslashes so they cannot neutralize the closing quote" do
      expect(described_class.eq("customer_name", "Acme\\")).to eq(%(customer_name = "Acme\\\\"))
      expect(described_class.eq("customer_name", %(Acme\\"))).to eq(%(customer_name = "Acme\\\\\\""))
    end
  end

  describe ".in_list" do
    it "builds a quoted IN list" do
      expect(described_class.in_list("status", %w[draft finalized])).to eq(%(status IN ["draft", "finalized"]))
    end

    it "wraps a single value in an array" do
      expect(described_class.in_list("status", "draft")).to eq(%(status IN ["draft"]))
    end
  end

  describe ".not_in_list" do
    it "builds a quoted NOT IN list" do
      expect(described_class.not_in_list("metadata_keys", %w[po])).to eq(%(metadata_keys NOT IN ["po"]))
    end
  end

  describe "comparisons" do
    it "builds bare numeric comparisons" do
      expect(described_class.gt("due_amount_cents", 0)).to eq("due_amount_cents > 0")
      expect(described_class.gte("issuing_date", 100)).to eq("issuing_date >= 100")
      expect(described_class.lt("total_amount_cents", 5)).to eq("total_amount_cents < 5")
      expect(described_class.lte("due_amount_cents", 0)).to eq("due_amount_cents <= 0")
    end
  end

  describe ".boolean" do
    it "casts truthy and falsey inputs" do
      expect(described_class.boolean("true")).to be(true)
      expect(described_class.boolean("f")).to be(false)
    end
  end

  describe ".literal" do
    it "is private" do
      expect { described_class.literal("value") }.to raise_error(NoMethodError)
    end
  end
end
