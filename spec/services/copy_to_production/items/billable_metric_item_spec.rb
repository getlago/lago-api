# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::BillableMetricItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:metric) { create(:billable_metric, organization: sandbox, code: "api_calls") }

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("billable_metric")
    expect(item.activity_type).to eq("billable_metric.copied_to_production")
  end

  describe "#find_source" do
    it "finds a metric of the sandbox" do
      expect(item.find_source(metric.id)).to eq(metric)
    end

    it "ignores a metric of production" do
      expect(item.find_source(create(:billable_metric, organization: production).id)).to be_nil
    end
  end

  describe "#find_existing" do
    let!(:live_metric) { create(:billable_metric, organization: production, code: "api_calls") }

    it "finds the kept production metric with the same code" do
      expect(item.find_existing(metric)).to eq(live_metric)
    end

    context "when the production metric is deleted" do
      before { live_metric.discard! }

      it "finds nothing" do
        expect(item.find_existing(metric)).to be_nil
      end
    end
  end
end
