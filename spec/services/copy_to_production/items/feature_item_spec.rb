# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::FeatureItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:feature) { create(:feature, organization: sandbox, code: "seats") }

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("feature")
    expect(item.activity_type).to eq("feature.copied_to_production")
  end

  it "has neither dependencies nor parent" do
    expect(item.dependencies(feature)).to eq([])
    expect(item.parent(feature)).to be_nil
  end

  describe "#find_source" do
    it "finds a feature of the sandbox" do
      expect(item.find_source(feature.id)).to eq(feature)
    end

    it "ignores a feature of production" do
      expect(item.find_source(create(:feature, organization: production).id)).to be_nil
    end
  end

  describe "#find_existing" do
    let(:live_feature) { create(:feature, organization: production, code: "seats") }

    before { live_feature }

    it "finds the kept production feature with the same code" do
      expect(item.find_existing(feature)).to eq(live_feature)
    end

    context "when the production feature is deleted" do
      before { live_feature.discard! }

      it "finds nothing" do
        expect(item.find_existing(feature)).to be_nil
      end
    end
  end

  describe "#copy!" do
    subject(:copy) { item.copy!(feature, {}) }

    before do
      create(:privilege, feature:, code: "max", name: "Maximum", value_type: "integer", created_at: 2.days.ago)
      create(:privilege, feature:, code: "tier", value_type: "select", config: {select_options: %w[free pro]}, created_at: 1.day.ago)
      create(:privilege, feature:, code: "removed").discard!
    end

    it "creates the feature and its kept privileges in production" do
      expect(copy).to have_attributes(
        organization_id: production.id,
        code: "seats",
        name: "Feature Name",
        description: "Feature Description"
      )
      expect(copy.privileges.order(:created_at, :id).map { it.slice(:code, :name, :value_type, :config, :organization_id) }).to eq(
        [
          {"code" => "max", "name" => "Maximum", "value_type" => "integer", "config" => {}, "organization_id" => production.id},
          {"code" => "tier", "name" => nil, "value_type" => "select", "config" => {"select_options" => %w[free pro]}, "organization_id" => production.id}
        ]
      )
    end
  end
end
