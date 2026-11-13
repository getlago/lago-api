# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::ValidateNameService do
  subject(:result) { described_class.call(name:) }

  let(:name) { "Acme Corp" }

  it "returns the name" do
    expect(result).to be_success
    expect(result.name).to eq("Acme Corp")
  end

  context "with invisible characters, control characters and extra spaces" do
    let(:name) { "  Acme​   \u0007Corp\t " }

    it "returns the cleaned name" do
      expect(result.name).to eq("Acme Corp")
    end
  end

  context "with a control character between two spaces" do
    let(:name) { "Acme \u0001 Corp" }

    it "leaves a single space" do
      expect(result.name).to eq("Acme Corp")
    end
  end

  context "with the zero-width joiners of a Persian name" do
    let(:name) { "Rang\u200Cava" }

    it "keeps them" do
      expect(result.name).to eq("Rang\u200Cava")
    end
  end

  ["", nil, "   ", "​­", "\u200C\u200D"].each do |blank|
    context "with #{blank.inspect}" do
      let(:name) { blank }

      it "refuses it as mandatory" do
        expect(result.error.messages).to eq(name: ["value_is_mandatory"])
      end
    end
  end

  context "with 100 characters" do
    let(:name) { "a" * 100 }

    it { is_expected.to be_success }
  end

  context "with 101 characters" do
    let(:name) { "a" * 101 }

    it "refuses it as too long" do
      expect(result.error.messages).to eq(name: ["value_is_too_long"])
      expect(result.error.meta).to eq(name: {max_length: 100})
    end
  end

  it "refuses names that carry a link" do
    links = ["https://acme.example", "Acme www.acme", "acme.com", "Visit acme.co.uk", "ａｃｍｅ．ｃｏｍ",
      "contact@acme.io", "Visit 10.0.0.1", "acme。com", "acme\u200D.com", "acme.com.ltd", "acme.io", "booking.com",
      "Dr.Ing Consulting", "javascript:alert(1)", "mailto:x@y", "Data:text/html,hi", "vbscript:x", "file:x"]

    expect(links.index_with { described_class.call(name: it).error&.messages })
      .to eq(links.index_with { {name: ["value_contains_link"]} })
  end

  it "accepts names with dots that are not links" do
    names = ["Acme Inc.", "A.B. Consulting", "Node.js Labs", "Version 2.0", "Release 1.2.3", "Acme Co.Ltd", "Acme.Inc",
      "Acme Pty.Ltd", "Muster GmbH & Co.KG", "Metadata:Labs"]

    expect(names.index_with { described_class.call(name: it).name }).to eq(names.index_with { it })
  end
end
