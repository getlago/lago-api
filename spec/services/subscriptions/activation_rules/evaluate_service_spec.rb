# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::EvaluateService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "stripe") }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) { create(:subscription, :activating, customer:, plan:, organization:) }

  describe "#call" do
    context "when there are no activation rules" do
      it "returns successfully with no applicable rules" do
        expect(result).to be_success
        expect(result.has_applicable_rules).to be_nil
      end
    end

    context "when there is a payment_required rule" do
      let!(:rule) { create(:subscription_activation_rule, subscription:, organization:, rule_type: "payment_required") }

      context "when the plan is pay_in_advance and customer has a payment provider" do
        it "marks the rule as pending" do
          expect(result).to be_success
          expect(result.has_applicable_rules).to be(true)
          expect(rule.reload.status).to eq("pending")
        end

        context "with timeout_hours" do
          let!(:rule) do
            create(:subscription_activation_rule, subscription:, organization:, rule_type: "payment_required", timeout_hours: 48)
          end

          it "sets expires_at based on timeout_hours" do
            freeze_time do
              result
              expect(rule.reload.expires_at).to eq(Time.current + 48.hours)
            end
          end
        end
      end

      context "when the plan is pay_in_arrears with no advance fixed charges" do
        let(:plan) { create(:plan, organization:, pay_in_advance: false) }

        it "marks the rule as not_applicable" do
          expect(result).to be_success
          expect(result.has_applicable_rules).to be(false)
          expect(rule.reload.status).to eq("not_applicable")
        end
      end

      context "when the subscription is in trial period" do
        before do
          allow(subscription).to receive(:in_trial_period?).and_return(true)
        end

        it "marks the rule as not_applicable" do
          expect(result).to be_success
          expect(result.has_applicable_rules).to be(false)
          expect(rule.reload.status).to eq("not_applicable")
        end
      end

      context "when the customer has no payment provider" do
        let(:customer) { create(:customer, organization:, payment_provider: nil) }

        it "raises a validation error" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:activation_rules]).to include("payment_provider_required_for_payment_rule")
        end
      end
    end
  end
end
