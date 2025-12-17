# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::UpdateUsageThresholdsService do
  subject(:result) { described_class.call(plan:, usage_thresholds_params:, partial:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:partial) { false }

  before do
    allow(LifetimeUsages::FlagRefreshFromPlanUpdateJob).to receive(:perform_after_commit).with(plan)
  end

  shared_context "with progressive_billing enabled" do
    around { |test| premium_integration!(organization, "progressive_billing", &test) }
  end

  describe "adding new thresholds" do
    include_context "with progressive_billing enabled"
    let(:usage_thresholds_params) do
      [
        {threshold_display_name: "First", amount_cents: 100},
        {threshold_display_name: "Second", amount_cents: 200}
      ]
    end

    it "creates new thresholds" do
      expect { result }.to change { plan.usage_thresholds.count }.from(0).to(2)

      thresholds = result.plan.usage_thresholds.order(:amount_cents)
      expect(thresholds.first.threshold_display_name).to eq("First")
      expect(thresholds.first.amount_cents).to eq(100)
      expect(thresholds.first.recurring).to be(false)
      expect(thresholds.second.threshold_display_name).to eq("Second")
      expect(thresholds.second.amount_cents).to eq(200)
      expect(thresholds.second.recurring).to be(false)
    end

    it "triggers the lifetime usage refresh job" do
      result
      expect(LifetimeUsages::FlagRefreshFromPlanUpdateJob).to have_received(:perform_after_commit).with(plan)
    end
  end

  describe "updating existing thresholds" do
    include_context "with progressive_billing enabled"
    let!(:existing_threshold) { create(:usage_threshold, plan:, amount_cents: 100, threshold_display_name: "Original") }
    let(:usage_thresholds_params) do
      [{threshold_display_name: "Updated", amount_cents: 100}]
    end

    it "updates the threshold display name" do
      expect { result }.not_to change { plan.usage_thresholds.count }

      threshold = result.plan.usage_thresholds.first
      expect(threshold.threshold_display_name).to eq("Updated")
      expect(threshold.amount_cents).to eq(100)
    end

    context "when changing amount_cents" do
      let(:usage_thresholds_params) do
        [{threshold_display_name: "Updated", amount_cents: 150}]
      end

      it "creates a new threshold and removes the old one (in full mode)" do
        expect { result }.not_to change { plan.usage_thresholds.count }

        threshold = result.plan.usage_thresholds.first
        expect(threshold.amount_cents).to eq(150)
        expect(existing_threshold.reload.deleted_at).to be_present
      end
    end
  end

  describe "partial vs full mode" do
    include_context "with progressive_billing enabled"
    let!(:threshold_100) { create(:usage_threshold, plan:, amount_cents: 100, threshold_display_name: "Keep100") }
    let!(:threshold_200) { create(:usage_threshold, plan:, amount_cents: 200, threshold_display_name: "Keep200") }

    context "when full mode (partial: false)" do
      let(:partial) { false }
      let(:usage_thresholds_params) do
        [{threshold_display_name: "New300", amount_cents: 300}]
      end

      it "removes thresholds not in params" do
        result

        expect(result.plan.usage_thresholds.count).to eq(1)
        expect(result.plan.usage_thresholds.first.amount_cents).to eq(300)
        expect(threshold_100.reload.deleted_at).to be_present
        expect(threshold_200.reload.deleted_at).to be_present
      end
    end

    context "when partial mode (partial: true)" do
      let(:partial) { true }
      let(:usage_thresholds_params) do
        [{threshold_display_name: "New300", amount_cents: 300}]
      end

      it "keeps thresholds not in params" do
        result

        expect(result.plan.usage_thresholds.count).to eq(3)
        amounts = result.plan.usage_thresholds.pluck(:amount_cents).sort
        expect(amounts).to eq([100, 200, 300])
      end
    end

    context "when partial mode with empty params" do
      let(:partial) { true }
      let(:usage_thresholds_params) { [] }

      it "does nothing" do
        expect { result }.not_to change { plan.usage_thresholds.count }
        expect(LifetimeUsages::FlagRefreshFromPlanUpdateJob).not_to have_received(:perform_after_commit)
      end
    end
  end

  describe "recurring thresholds" do
    include_context "with progressive_billing enabled"

    context "when adding a recurring threshold" do
      let(:usage_thresholds_params) do
        [{threshold_display_name: "Recurring", amount_cents: 100, recurring: true}]
      end

      it "creates a recurring threshold" do
        result

        threshold = result.plan.usage_thresholds.first
        expect(threshold.recurring).to be(true)
        expect(threshold.amount_cents).to eq(100)
      end
    end

    context "when updating an existing recurring threshold" do
      let!(:recurring_threshold) { create(:usage_threshold, :recurring, plan:, amount_cents: 100, threshold_display_name: "Original") }
      let(:usage_thresholds_params) do
        [{threshold_display_name: "Updated", amount_cents: 200, recurring: true}]
      end

      it "updates the existing recurring threshold" do
        expect { result }.not_to change { plan.usage_thresholds.count }

        threshold = result.plan.usage_thresholds.recurring.first
        expect(threshold.threshold_display_name).to eq("Updated")
        expect(threshold.amount_cents).to eq(200)
      end
    end

    context "when a recurring and non-recurring threshold have the same amount_cents" do
      let!(:non_recurring_threshold) { create(:usage_threshold, plan:, amount_cents: 100, recurring: false) }
      let(:usage_thresholds_params) do
        [
          {threshold_display_name: "Non-recurring", amount_cents: 100, recurring: false},
          {threshold_display_name: "Recurring", amount_cents: 100, recurring: true}
        ]
      end

      it "treats them as different thresholds" do
        result

        expect(result.plan.usage_thresholds.count).to eq(2)
        non_recurring = result.plan.usage_thresholds.not_recurring.first
        recurring = result.plan.usage_thresholds.recurring.first

        expect(non_recurring.threshold_display_name).to eq("Non-recurring")
        expect(recurring.threshold_display_name).to eq("Recurring")
      end
    end
  end

  describe "validation errors" do
    include_context "with progressive_billing enabled"

    context "when there are duplicate amount_cents with same recurring value" do
      let(:usage_thresholds_params) do
        [
          {threshold_display_name: "First", amount_cents: 100, recurring: false},
          {threshold_display_name: "Second", amount_cents: 100, recurring: false}
        ]
      end

      it "returns a validation error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:usage_thresholds]).to include("duplicated_values")
      end

      it "does not create any thresholds" do
        expect { result }.not_to change { plan.usage_thresholds.count }
      end
    end

    context "when there are multiple recurring thresholds" do
      let(:usage_thresholds_params) do
        [
          {threshold_display_name: "First recurring", amount_cents: 100, recurring: true},
          {threshold_display_name: "Second recurring", amount_cents: 200, recurring: true}
        ]
      end

      it "returns a validation error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:usage_thresholds]).to include("multiple_recurring_thresholds")
      end

      it "does not create any thresholds" do
        expect { result }.not_to change { plan.usage_thresholds.count }
      end
    end

    context "when same amount_cents but different recurring values" do
      let(:usage_thresholds_params) do
        [
          {threshold_display_name: "Non-recurring", amount_cents: 100, recurring: false},
          {threshold_display_name: "Recurring", amount_cents: 100, recurring: true}
        ]
      end

      it "is valid and creates both thresholds" do
        expect(result).to be_success
        expect(result.plan.usage_thresholds.count).to eq(2)
      end
    end
  end

  describe "result attributes" do
    include_context "with progressive_billing enabled"
    let(:usage_thresholds_params) { [{threshold_display_name: "Test", amount_cents: 100}] }

    it "returns the plan" do
      expect(result.plan).to eq(plan)
    end

    it "returns the partial flag" do
      expect(result.partial).to eq(partial)
    end

    context "when partial is true" do
      let(:partial) { true }

      it "returns partial as true" do
        expect(result.partial).to be(true)
      end
    end
  end

  describe "edge cases" do
    context "when plan is a child plan" do
      include_context "with progressive_billing enabled"
      let(:parent_plan) { create(:plan, organization:) }
      let(:plan) { create(:plan, organization:, parent: parent_plan) }
      let(:usage_thresholds_params) { [{threshold_display_name: "Test", amount_cents: 100}] }

      it "returns early without changes" do
        expect { result }.not_to change { UsageThreshold.count }
        expect(LifetimeUsages::FlagRefreshFromPlanUpdateJob).not_to have_received(:perform_after_commit)
      end
    end

    context "when progressive_billing is not enabled" do
      let(:usage_thresholds_params) { [{threshold_display_name: "Test", amount_cents: 100}] }

      it "returns early without changes" do
        expect { result }.not_to change { UsageThreshold.count }
      end
    end

    context "when updating a threshold changes its recurring status" do
      include_context "with progressive_billing enabled"
      let!(:non_recurring_threshold) { create(:usage_threshold, plan:, amount_cents: 100, recurring: false) }
      let(:usage_thresholds_params) do
        [{threshold_display_name: "Now recurring", amount_cents: 100, recurring: true}]
      end

      it "creates a new recurring threshold and deletes the old one in full mode" do
        result

        expect(result.plan.usage_thresholds.count).to eq(1)
        threshold = result.plan.usage_thresholds.first
        expect(threshold.recurring).to be(true)
        expect(non_recurring_threshold.reload.deleted_at).to be_present
      end
    end

    context "when threshold_display_name is nil" do
      include_context "with progressive_billing enabled"
      let(:usage_thresholds_params) do
        [{amount_cents: 100, recurring: false}]
      end

      it "creates a threshold with nil display name" do
        result

        threshold = result.plan.usage_thresholds.first
        expect(threshold.threshold_display_name).to be_nil
        expect(threshold.amount_cents).to eq(100)
      end
    end

    context "when params contain extra fields" do
      include_context "with progressive_billing enabled"
      let(:usage_thresholds_params) do
        [{threshold_display_name: "Test", amount_cents: 100, extra_field: "ignored", another: 123}]
      end

      it "ignores extra fields" do
        result

        expect(result.plan.usage_thresholds.count).to eq(1)
        threshold = result.plan.usage_thresholds.first
        expect(threshold.threshold_display_name).to eq("Test")
        expect(threshold.amount_cents).to eq(100)
      end
    end

    context "when mixing additions, updates, and deletions in full mode" do
      include_context "with progressive_billing enabled"
      let!(:keep_threshold) { create(:usage_threshold, plan:, amount_cents: 100, threshold_display_name: "Keep") }
      let!(:update_threshold) { create(:usage_threshold, plan:, amount_cents: 200, threshold_display_name: "Update") }
      let!(:delete_threshold) { create(:usage_threshold, plan:, amount_cents: 300, threshold_display_name: "Delete") }
      let(:usage_thresholds_params) do
        [
          {threshold_display_name: "Keep", amount_cents: 100},
          {threshold_display_name: "Updated", amount_cents: 200},
          {threshold_display_name: "New", amount_cents: 400}
        ]
      end

      it "performs all operations correctly" do
        result

        thresholds = result.plan.usage_thresholds.order(:amount_cents)
        expect(thresholds.count).to eq(3)

        expect(thresholds[0].threshold_display_name).to eq("Keep")

        expect(thresholds[1].threshold_display_name).to eq("Updated")

        expect(thresholds[2].amount_cents).to eq(400)
        expect(thresholds[2].threshold_display_name).to eq("New")

        expect(delete_threshold.reload.deleted_at).to be_present
      end
    end
  end
end
