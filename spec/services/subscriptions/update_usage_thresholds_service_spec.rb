# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::UpdateUsageThresholdsService do
  subject(:result) { described_class.call(subscription:, usage_thresholds_params:, partial:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, plan:, organization:) }
  let(:partial) { false }

  describe "#call" do
    context "when progressive_billing is not enabled" do
      context "when usage_thresholds_params is empty" do
        let(:usage_thresholds_params) { [] }

        it "does not create thresholds" do
          expect(result.subscription.usage_thresholds).to be_empty
        end
      end

      context "when usage_thresholds_params is not empty" do
        let(:usage_thresholds_params) do
          [
            {
              threshold_display_name: "Threshold 1",
              amount_cents: 1000
            }
          ]
        end

        it "does not create thresholds" do
          expect(result.subscription.usage_thresholds).to be_empty
        end
      end
    end

    context "when progressive_billing is enabled" do
      around { |test| premium_integration!(organization, "progressive_billing", &test) }

      context "when usage_thresholds_params is empty" do
        let(:usage_thresholds_params) { [] }

        it "does not create thresholds" do
          expect(result.subscription.usage_thresholds).to be_empty
        end

        context "when subscription has existing thresholds" do
          let!(:threshold1) do
            create(:usage_threshold, :for_subscription, subscription:, threshold_display_name: "Threshold 1", amount_cents: 1)
          end
          let!(:threshold2) do
            create(:usage_threshold, :for_subscription, subscription:, threshold_display_name: "Threshold 2", amount_cents: 2)
          end

          context "when partial is false" do
            let(:partial) { false }

            it "clears all thresholds" do
              expect(result.subscription.usage_thresholds).to be_empty
            end
          end

          context "when partial is true" do
            let(:partial) { true }

            it "keeps existing thresholds" do
              expect(result.subscription.usage_thresholds).to contain_exactly(threshold1, threshold2)
            end
          end
        end
      end

      context "when usage_thresholds_params is not empty" do
        let(:usage_thresholds_params) do
          [
            {
              threshold_display_name: "Threshold 1",
              amount_cents: 1000
            }
          ]
        end

        it "creates usage thresholds" do
          thresholds = result.subscription.usage_thresholds
          expect(thresholds.size).to eq(1)
          expect(thresholds.first.threshold_display_name).to eq("Threshold 1")
          expect(thresholds.first.amount_cents).to eq(1000)
        end

        it "flags lifetime usage for refresh" do
          lifetime_usage = create(:lifetime_usage, subscription:, organization:)

          expect { result }.to change { lifetime_usage.reload.recalculate_invoiced_usage }.from(false).to(true)
        end

        context "when subscription has existing thresholds" do
          before do
            create(:usage_threshold, :for_subscription, subscription:, threshold_display_name: "Existing", amount_cents: 500)
          end

          context "when partial is false" do
            let(:partial) { false }

            it "replaces existing thresholds with new ones" do
              thresholds = result.subscription.usage_thresholds
              expect(thresholds.size).to eq(1)
              expect(thresholds.first.threshold_display_name).to eq("Threshold 1")
              expect(thresholds.first.amount_cents).to eq(1000)
            end
          end

          context "when partial is true" do
            let(:partial) { true }

            it "merges new thresholds with existing ones" do
              thresholds = result.subscription.usage_thresholds.order(:amount_cents)
              expect(thresholds.size).to eq(2)
              expect(thresholds.first.amount_cents).to eq(500)
              expect(thresholds.last.amount_cents).to eq(1000)
            end
          end
        end

        context "when updating existing threshold by id" do
          let(:existing_threshold) do
            create(:usage_threshold, :for_subscription, subscription:, threshold_display_name: "Old Name", amount_cents: 500)
          end
          let(:usage_thresholds_params) do
            [
              {
                id: existing_threshold.id,
                threshold_display_name: "New Name",
                amount_cents: 600
              }
            ]
          end

          it "updates the existing threshold" do
            thresholds = result.subscription.usage_thresholds
            expect(thresholds.size).to eq(1)
            expect(thresholds.first.id).to eq(existing_threshold.id)
            expect(thresholds.first.threshold_display_name).to eq("New Name")
            expect(thresholds.first.amount_cents).to eq(600)
          end
        end

        context "when creating a recurring threshold" do
          let(:usage_thresholds_params) do
            [
              {
                threshold_display_name: "Recurring Threshold",
                amount_cents: 1000,
                recurring: true
              }
            ]
          end

          it "creates a recurring threshold" do
            thresholds = result.subscription.usage_thresholds
            expect(thresholds.size).to eq(1)
            expect(thresholds.first.recurring).to be true
          end

          context "when a recurring threshold already exists" do
            let!(:existing_recurring) do
              create(:usage_threshold, :for_subscription, :recurring, subscription:, threshold_display_name: "Existing Recurring", amount_cents: 500)
            end

            it "updates the existing recurring threshold instead of creating a new one" do
              thresholds = result.subscription.usage_thresholds.recurring
              expect(thresholds.size).to eq(1)
              expect(thresholds.first.id).to eq(existing_recurring.id)
              expect(thresholds.first.threshold_display_name).to eq("Recurring Threshold")
              expect(thresholds.first.amount_cents).to eq(1000)
            end
          end
        end

        context "when threshold was removed and re-added with same amount" do
          let(:usage_thresholds_params) do
            [
              {
                threshold_display_name: "New Threshold Same Amount",
                amount_cents: 1000
              }
            ]
          end

          it "finds existing threshold with same amount and updates it" do
            create(:usage_threshold, :for_subscription, subscription:, threshold_display_name: "Existing", amount_cents: 1000)

            thresholds = result.subscription.usage_thresholds
            expect(thresholds.size).to eq(1)
            expect(thresholds.first.amount_cents).to eq(1000)
            expect(thresholds.first.threshold_display_name).to eq("New Threshold Same Amount")
          end
        end
      end
    end
  end
end
