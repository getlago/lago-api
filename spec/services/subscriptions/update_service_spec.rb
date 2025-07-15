# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::UpdateService, type: :service do
  subject(:update_service) { described_class.new(subscription:, params:) }

  let(:membership) { create(:membership) }
  let(:subscription) { create(:subscription) }

  describe "#call" do
    let(:subscription_at) { "2022-07-07T00:00:00Z" }
    let(:ending_at) { Time.current.beginning_of_day + 1.month }

    let(:params) do
      {
        name: "new name",
        ending_at:,
        subscription_at:
      }
    end

    before do
      allow(Utils::ActivityLog).to receive(:produce).and_call_original

      subscription
    end

    context "when subscription is already active" do
      it "updates the subscription and ignores subscription_at" do
        result = update_service.call

        expect(result).to be_success

        expect(result.subscription.name).to eq("new name")
        expect(result.subscription.ending_at).to eq(Time.current.beginning_of_day + 1.month)
        expect(result.subscription.subscription_at.to_s).not_to include("2022-07-07")
      end

      it "sends updated subscription webhook" do
        expect { update_service.call }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
      end

      it "does not sync to Hubspot" do
        expect { update_service.call }.not_to have_enqueued_job(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob)
      end

      it "produces an activity log after commit" do
        described_class.call(subscription:, params:)

        expect(Utils::ActivityLog).to have_received(:produce).with(subscription, "subscription.updated", after_commit: true)
      end

      context "when subscription should be synced with Hubspot" do
        let(:params) { {name: "new name"} }
        let(:customer) { create(:customer, :with_hubspot_integration) }
        let(:subscription) { create(:subscription, customer:) }

        it "enqueues a job to update Hubspot subscription" do
          expect {
            result = update_service.call

            expect(result).to be_success
          }.to have_enqueued_job_after_commit(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob).with(subscription:)
        end
      end

      context "when subscription_at is not passed at all" do
        let(:params) { {name: "new name"} }

        it "updates the subscription" do
          result = update_service.call

          expect(result).to be_success

          expect(result.subscription.name).to eq("new name")
          expect(result.subscription.subscription_at.to_s).not_to include("2022-07-07")
        end
      end
    end

    context "when subscription is starting in the future" do
      let(:subscription) { create(:subscription, :pending) }

      it "does not produce activity log" do
        update_service.call

        expect(Utils::ActivityLog).not_to have_received(:produce)
      end

      context "when subscription is pay_in_advance" do
        let(:plan) { create(:plan, :pay_in_advance) }
        let(:subscription) { create(:subscription, :pending, plan:) }

        context "when subscription_at is set to past date" do
          it "updates the subscription_at as well" do
            result = update_service.call

            expect(result).to be_success

            expect(result.subscription.name).to eq("new name")
            expect(result.subscription.subscription_at.to_s).to eq("2022-07-07 00:00:00 UTC")
          end

          it "does not enqueue a job to bill the subscription" do
            expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end
        end

        context "when subscription date is set to today" do
          around do |test|
            travel_to("2022-07-07T01:00:00Z") do
              test.run
            end
          end

          it "activates subscription" do
            result = update_service.call

            expect(result).to be_success

            expect(result.subscription.name).to eq("new name")
            expect(result.subscription.status).to eq("active")
            expect(result.subscription.subscription_at.to_s).to eq subscription.subscription_at.to_s
          end

          it "enqueues a job to bill the subscription" do
            expect { update_service.call }.to have_enqueued_job_after_commit(BillSubscriptionJob)
              .with([subscription], Time.now.to_i, invoicing_reason: :subscription_starting)
          end
        end

        context "when subscription_at is set to future date" do
          let(:subscription_at) { 1.week.from_now.iso8601 }

          it "keeps subscription pending and updates subscription_at" do
            result = update_service.call

            expect(result).to be_success
            expect(result.subscription.status).to eq("pending")
            expect(result.subscription.subscription_at).to eq(subscription_at)
          end

          it "does not enqueue billing job" do
            expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end
        end
      end

      context "when plan is NOT pay_in_advance" do
        context "when subscription_at is today" do
          let(:subscription_at) { Time.current }

          it "does not enqueue billing job" do
            expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end
        end
      end

      context "when updating subscription without changing subscription_at" do
        let(:params) { {name: "new name"} }

        it "updates the subscription without processing subscription_at change" do
          result = update_service.call

          expect(result).to be_success
          expect(result.subscription.name).to eq("new name")
        end
      end
    end

    context "when subscription is nil" do
      let(:params) do
        {
          name: "new name"
        }
      end

      let(:subscription) { nil }

      it "returns an error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("subscription_not_found")
      end
    end

    context "when validation fails" do
      context "with invalid subscription_at format" do
        let(:params) { {subscription_at: "invalid-date"} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({subscription_at: ["invalid_date"]})
        end
      end

      context "with invalid ending_at format" do
        let(:params) { {ending_at: "invalid-date"} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({ending_at: ["invalid_date"]})
        end
      end

      context "with ending_at in the past" do
        let(:params) { {ending_at: 1.day.ago} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({ending_at: ["invalid_date"]})
        end
      end

      context "with ending_at before subscription_at" do
        let(:params) { {ending_at: 1.day.from_now, subscription_at: 2.days.from_now} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({ending_at: ["invalid_date"]})
        end
      end
    end

    context "when plan_overrides" do
      let(:plan) { create(:plan, organization: membership.organization) }
      let(:subscription) { create(:subscription, plan:) }
      let(:params) do
        {
          plan_overrides: {
            name: "new name"
          }
        }
      end

      context "when License is premium" do
        around { |test| lago_premium!(&test) }

        it "creates the new plan accordingly" do
          update_service.call

          expect(subscription.plan.name).to eq("new name")
          expect(subscription.plan_id).not_to eq(plan.id)
          expect(subscription.plan.parent_id).to eq(plan.id)
        end

        context "with overriden plan" do
          let(:parent_plan) { create(:plan, organization: membership.organization) }
          let(:plan) { create(:plan, organization: membership.organization, parent_id: parent_plan.id) }

          it "updates the plan accordingly" do
            update_service.call

            expect(subscription.plan.name).to eq("new name")
            expect(subscription.plan_id).to eq(plan.id)
          end
        end
      end

      context "when License is not premium" do
        let(:params) do
          {
            name: "new name",
            plan_overrides: {
              amount_cents: 0
            }
          }
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("feature_unavailable")
        end
      end
    end

    context "with empty params" do
      let(:params) { {} }

      it "succeeds without making changes" do
        original_name = subscription.name
        result = update_service.call

        expect(result).to be_success
        expect(result.subscription.name).to eq(original_name)
      end
    end

    context "with nil values in params" do
      let(:params) { {name: nil, ending_at: nil} }

      it "handles nil values gracefully" do
        result = update_service.call

        expect(result).to be_success
        expect(result.subscription.name).to be_nil
        expect(result.subscription.ending_at).to be_nil
      end
    end

    context "when customer is missing" do
      let(:subscription) { build(:subscription, customer: nil) }
      let(:params) { {name: "new name"} }

      it "returns customer not found error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end

    context "when plan is missing" do
      let(:subscription) { build(:subscription, plan: nil) }
      let(:params) { {name: "new name"} }

      it "returns plan not found error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end
  end
end
