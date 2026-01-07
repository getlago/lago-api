# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureFlag do
  let(:feature_hash) { {"feature1" => {"description" => "text"}}.with_indifferent_access.freeze }
  let(:organization) { create(:organization) }
  let(:feature_name) { "feature1" }

  before do
    stub_const("FeatureFlag::DEFINITION", feature_hash)
    Flipper.add(feature_name)
  end

  after { Flipper.remove(feature_name) }

  describe ".enabled?" do
    context "when feature is enabled globally" do
      before { Flipper.enable(feature_name) }

      it "returns true" do
        expect(described_class.enabled?(feature_name, organization:)).to be(true)
      end
    end

    context "when feature is disabled globally" do
      before { Flipper.disable(feature_name) }

      it "returns false" do
        expect(described_class.enabled?(feature_name, organization:)).to be(false)
      end
    end

    context "when feature is enabled for a specific actor" do
      before { Flipper.enable(feature_name, organization) }

      it do
        expect(described_class.enabled?(feature_name, organization:)).to be(true)
        expect(described_class.enabled?(feature_name, organization: create(:organization))).to be(false)
      end
    end

    context "when feature flag does not exist in definition" do
      it "raises an error in non-production" do
        expect { described_class.enabled?("unknown_feature", organization:) }.to raise_error("Unknown feature flag: unknown_feature")
      end
    end
  end

  describe ".disabled?" do
    context "when feature is enabled" do
      before { Flipper.enable(feature_name) }

      it "returns false" do
        expect(described_class.disabled?(feature_name, organization:)).to be(false)
      end
    end

    context "when feature is disabled" do
      before { Flipper.disable(feature_name) }

      it "returns true" do
        expect(described_class.disabled?(feature_name, organization:)).to be(true)
      end
    end

    context "when feature is enabled for a specific actor" do
      before { Flipper.enable(feature_name, organization) }

      it "returns false for the actor" do
        expect(described_class.disabled?(feature_name, organization:)).to be(false)
        expect(described_class.disabled?(feature_name, organization: create(:organization))).to be(true)
      end
    end
  end

  describe ".enable" do
    it "enables the feature for a specific actor" do
      described_class.enable(feature_name, organization:)

      expect(Flipper.enabled?(feature_name, organization)).to be(true)
      expect(Flipper.enabled?(feature_name, create(:organization))).to be(false)
    end

    context "when feature flag does not exist in definition" do
      it "raises an error in non-production" do
        expect { described_class.enable("unknown_feature", organization:) }.to raise_error("Unknown feature flag: unknown_feature")
      end
    end
  end

  describe ".disable" do
    it "disables the feature for a specific actor" do
      Flipper.enable(feature_name, organization)
      described_class.disable(feature_name, organization:)

      expect(Flipper.enabled?(feature_name, organization)).to be(false)
    end

    context "when feature flag does not exist in definition" do
      it "raises an error in non-production" do
        expect { described_class.disable("unknown_feature", organization:) }.to raise_error("Unknown feature flag: unknown_feature")
      end
    end
  end

  describe ".sanitize!" do
    it "adds missing features from definition" do
      Flipper.remove(feature_name)

      expect { described_class.sanitize! }.to change { Flipper.features.map(&:key) }.from([]).to([feature_name])
    end

    it "removes features not in definition" do
      Flipper.add("obsolete_feature")

      expect { described_class.sanitize! }.to change { Flipper.features.map(&:key).sort }
        .from(match_array([feature_name, "obsolete_feature"]))
        .to([feature_name])
    end

    it "returns self" do
      expect(described_class.sanitize!).to eq(described_class)
    end
  end
end
