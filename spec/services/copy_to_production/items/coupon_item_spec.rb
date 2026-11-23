# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::CouponItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:coupon) { create(:coupon, organization: sandbox, code: "welcome") }

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("coupon")
    expect(item.activity_type).to eq("coupon.copied_to_production")
  end

  describe "#find_source" do
    it "finds a coupon of the sandbox" do
      expect(item.find_source(coupon.id)).to eq(coupon)
    end

    it "ignores a coupon of production" do
      expect(item.find_source(create(:coupon, organization: production).id)).to be_nil
    end
  end

  describe "#find_existing" do
    let!(:live_coupon) { create(:coupon, organization: production, code: "welcome") }

    it "finds the kept production coupon with the same code" do
      expect(item.find_existing(coupon)).to eq(live_coupon)
    end

    context "when the production coupon is deleted" do
      before { live_coupon.discard! }

      it "finds nothing" do
        expect(item.find_existing(coupon)).to be_nil
      end
    end
  end

  describe "#dependencies" do
    let(:metric) { create(:billable_metric, organization: sandbox) }
    let(:deleted_metric) { create(:billable_metric, organization: sandbox) }

    before do
      create(:coupon_billable_metric, coupon:, billable_metric: metric)
      create(:coupon_billable_metric, coupon:, billable_metric: deleted_metric)
      deleted_metric.discard!
    end

    it "lists the kept targeted metrics" do
      expect(item.dependencies(coupon.reload)).to eq([["billable_metric", metric]])
    end
  end

  describe "#refusal" do
    it "accepts a coupon without targets" do
      expect(item.refusal(coupon)).to be_nil
    end

    context "when the coupon targets a billable metric" do
      before { create(:coupon_billable_metric, coupon:, billable_metric: create(:billable_metric, organization: sandbox)) }

      it "accepts it" do
        expect(item.refusal(coupon.reload)).to be_nil
      end
    end

    context "when the coupon targets a legacy plan" do
      before { create(:coupon_plan, coupon:, plan: create(:plan, organization: sandbox)) }

      it "refuses it" do
        expect(item.refusal(coupon.reload)).to eq("copy_to_production_unsupported_target")
      end
    end

    context "when the coupon targets a catalog plan" do
      before { create(:coupon_catalog_plan, coupon:, catalog_plan: create(:catalog_plan, organization: sandbox)) }

      it "refuses it" do
        expect(item.refusal(coupon.reload)).to eq("copy_to_production_unsupported_target")
      end
    end
  end
end
