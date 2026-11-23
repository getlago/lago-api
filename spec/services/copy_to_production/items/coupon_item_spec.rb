# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::CouponItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:coupon) { create(:coupon, organization: sandbox, code: "welcome") }

  it_behaves_like "a copy to production item matched by code", :coupon

  # The expiration date is copied only for a time limit; targets are remapped; a copy starts active.
  it_behaves_like "a copy to production item copying every column", Coupon,
    left_out: %w[expiration_at limited_billable_metrics limited_plans status terminated_at]

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("coupon")
    expect(item.activity_type).to eq("coupon.copied_to_production")
  end

  describe "#dependencies" do
    let(:metric) { create(:billable_metric, organization: sandbox, code: "storage") }
    let(:other_metric) { create(:billable_metric, organization: sandbox, code: "seats") }
    let(:deleted_metric) { create(:billable_metric, organization: sandbox) }

    before do
      create(:coupon_billable_metric, coupon:, billable_metric: metric)
      create(:coupon_billable_metric, coupon:, billable_metric: other_metric)
      create(:coupon_billable_metric, coupon:, billable_metric: deleted_metric)
      deleted_metric.discard!
    end

    it "lists the kept targeted metrics by code" do
      expect(item.dependencies(coupon.reload)).to eq([["billable_metric", other_metric], ["billable_metric", metric]])
    end
  end

  describe "#parents" do
    let(:pro) { create(:catalog_plan, organization: sandbox, code: "pro") }
    let(:basic) { create(:catalog_plan, organization: sandbox, code: "basic") }
    let(:deleted_plan) { create(:catalog_plan, organization: sandbox, code: "old") }

    before do
      create(:coupon_catalog_plan, coupon:, catalog_plan: pro)
      create(:coupon_catalog_plan, coupon:, catalog_plan: basic)
      create(:coupon_catalog_plan, coupon:, catalog_plan: deleted_plan)
      deleted_plan.discard!
    end

    it "lists the kept targeted catalog plans by code" do
      expect(item.parents(coupon.reload)).to eq([["catalog_plan", basic], ["catalog_plan", pro]])
    end
  end

  describe "#refusal" do
    it "accepts a coupon without targets" do
      expect(item.refusal(coupon)).to be_nil
    end

    context "when the coupon targets billable metrics" do
      let(:coupon) { create(:coupon, organization: sandbox, code: "welcome", limited_billable_metrics: true) }
      let(:metric) { create(:billable_metric, organization: sandbox) }
      let(:other_metric) { create(:billable_metric, organization: sandbox) }

      before do
        create(:coupon_billable_metric, coupon:, billable_metric: metric)
        create(:coupon_billable_metric, coupon:, billable_metric: other_metric)
      end

      it "accepts it" do
        expect(item.refusal(coupon.reload)).to be_nil
      end

      context "when some of them are deleted" do
        before { metric.discard! }

        it "accepts it" do
          expect(item.refusal(coupon.reload)).to be_nil
        end
      end

      context "when all of them are deleted" do
        before do
          metric.discard!
          other_metric.discard!
        end

        it "refuses it" do
          expect(item.refusal(coupon.reload)).to eq("copy_to_production_target_deleted")
        end
      end
    end

    context "when the coupon is terminated" do
      let(:coupon) { create(:coupon, organization: sandbox, code: "welcome", status: "terminated", terminated_at: Time.current) }

      it "refuses it" do
        expect(item.refusal(coupon)).to eq("copy_to_production_item_inactive")
      end
    end

    context "when the coupon has expired" do
      let(:coupon) do
        create(:coupon, organization: sandbox, code: "welcome", expiration: "time_limit", expiration_at: 1.day.ago)
      end

      it "refuses it" do
        expect(item.refusal(coupon)).to eq("copy_to_production_item_inactive")
      end
    end

    context "when a coupon without expiration keeps a past date" do
      let(:coupon) do
        create(:coupon, organization: sandbox, code: "welcome", expiration: "no_expiration", expiration_at: 1.day.ago)
      end

      it "accepts it" do
        expect(item.refusal(coupon)).to be_nil
      end
    end

    context "when the coupon expires later" do
      let(:coupon) do
        create(:coupon, organization: sandbox, code: "welcome", expiration: "time_limit", expiration_at: 1.day.from_now)
      end

      it "accepts it" do
        expect(item.refusal(coupon)).to be_nil
      end
    end

    context "when the coupon targets a legacy plan" do
      before { create(:coupon_plan, coupon:, plan: create(:plan, organization: sandbox)) }

      it "refuses it" do
        expect(item.refusal(coupon.reload)).to eq("copy_to_production_unsupported_target")
      end
    end

    context "when the coupon targets catalog plans" do
      let(:plan) { create(:catalog_plan, organization: sandbox) }
      let(:other_plan) { create(:catalog_plan, organization: sandbox) }

      before do
        create(:coupon_catalog_plan, coupon:, catalog_plan: plan)
        create(:coupon_catalog_plan, coupon:, catalog_plan: other_plan)
      end

      it "accepts it" do
        expect(item.refusal(coupon.reload)).to be_nil
      end

      context "when all of them are deleted" do
        before do
          plan.discard!
          other_plan.discard!
        end

        it "refuses it" do
          expect(item.refusal(coupon.reload)).to eq("copy_to_production_target_deleted")
        end
      end
    end
  end
end
