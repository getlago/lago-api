# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributions::LabelsService do
  subject(:labels) { described_class.call!(attribution_types:, properties:).labels }

  let(:organization) { create(:organization) }
  let(:department) { create(:usage_attribution_type, organization:, code: "department", attribution_keys: ["department_id"]) }
  let(:user) { create(:usage_attribution_type, organization:, code: "user", attribution_keys: %w[user_id userId], parent: department) }
  let(:model) { create(:flat_usage_attribution_type, organization:, code: "model", attribution_keys: ["model"]) }
  let(:attribution_types) { [department, user, model] }

  context "with the full chain and a flat key" do
    let(:properties) { {"department_id" => "rnd", "user_id" => "alice", "model" => "opus", "tokens" => 1000} }

    it "resolves the labels keyed by type code" do
      expect(labels).to eq("department" => "rnd", "user" => "alice", "model" => "opus")
    end
  end

  context "with part of the chain" do
    let(:properties) { {"user_id" => "alice"} }

    it "only resolves the types found in the properties" do
      expect(labels).to eq("user" => "alice")
    end
  end

  context "with the second attribution key of a type" do
    let(:properties) { {"userId" => "bob"} }

    it "falls back on it" do
      expect(labels).to eq("user" => "bob")
    end
  end

  context "with several attribution keys of a type" do
    let(:properties) { {"user_id" => "alice", "userId" => "bob"} }

    it "uses the first one" do
      expect(labels).to eq("user" => "alice")
    end
  end

  context "when the first attribution key is empty" do
    let(:properties) { {"user_id" => "", "userId" => "bob"} }

    it "falls back on the next one" do
      expect(labels).to eq("user" => "bob")
    end
  end

  context "with numeric and boolean values" do
    let(:properties) { {"department_id" => 1234567, "user_id" => 1.0, "model" => true} }

    it "formats them like the events-processor" do
      expect(labels).to eq("department" => "1234567", "user" => "1", "model" => "true")
    end
  end

  context "with decimal values" do
    let(:properties) { {"department_id" => 12.5, "user_id" => 0.00001, "model" => 1e21} }

    it "formats them in plain decimal notation" do
      expect(labels).to eq("department" => "12.5", "user" => "0.00001", "model" => "1000000000000000000000")
    end
  end

  context "with null, nested and too long values" do
    let(:properties) { {"department_id" => nil, "user_id" => {"id" => "alice"}, "userId" => ["bob"], "model" => "a" * 256} }

    it "skips them" do
      expect(labels).to eq({})
    end
  end

  context "with a value at the maximum length" do
    let(:properties) { {"model" => "é" * 255} }

    it "counts the length in characters" do
      expect(labels).to eq("model" => "é" * 255)
    end
  end

  context "without properties" do
    let(:properties) { nil }

    it "resolves no labels" do
      expect(labels).to eq({})
    end
  end
end
