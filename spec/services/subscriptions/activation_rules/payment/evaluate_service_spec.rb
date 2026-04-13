# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::Payment::EvaluateService do
  subject(:result) { described_class.call(rule:, status:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) { create(:subscription, :incomplete, organization:, customer:, plan:) }
  let(:rule) { create(:payment_subscription_activation_rule, subscription:, status: rule_status, timeout_hours:) }
  let(:rule_status) { "inactive" }
  let(:timeout_hours) { 48 }
  let(:status) { nil }

  context "when rule is inactive" do
    let(:rule_status) { "inactive" }

    context "when rule is applicable (pay-in-advance plan, no trial)" do
      it "transitions rule to pending" do
        expect(result).to be_success
        expect(rule.reload.status).to eq("pending")
      end

      it "sets expires_at based on timeout_hours" do
        freeze_time do
          result

          expect(rule.reload.expires_at).to eq(Time.current + 48.hours)
        end
      end

      context "when timeout_hours is zero" do
        let(:timeout_hours) { 0 }

        it "transitions rule to pending without expires_at" do
          result

          expect(rule.reload).to have_attributes(status: "pending", expires_at: nil)
        end
      end
    end

    context "when rule is applicable (pay-in-arrears plan with pay-in-advance fixed charges)" do
      let(:plan) { create(:plan, organization:, pay_in_advance: false) }
      let(:add_on) { create(:add_on, organization:) }

      before { create(:fixed_charge, plan:, add_on:, pay_in_advance: true) }

      it "transitions rule to pending" do
        result

        expect(rule.reload.status).to eq("pending")
      end
    end

    context "when rule is not applicable (pay-in-arrears plan, no fixed charges)" do
      let(:plan) { create(:plan, organization:, pay_in_advance: false) }

      it "transitions rule to not_applicable" do
        result

        expect(rule.reload.status).to eq("not_applicable")
      end
    end

    context "when rule is not applicable (pay-in-advance plan with trial period)" do
      let(:plan) { create(:plan, organization:, pay_in_advance: true, trial_period: 30) }

      it "transitions rule to not_applicable" do
        result

        expect(rule.reload.status).to eq("not_applicable")
      end
    end

    context "when plan has trial but has pay-in-advance fixed charges" do
      let(:plan) { create(:plan, organization:, pay_in_advance: true, trial_period: 30) }
      let(:add_on) { create(:add_on, organization:) }

      before { create(:fixed_charge, plan:, add_on:, pay_in_advance: true) }

      it "transitions rule to pending" do
        result

        expect(rule.reload.status).to eq("pending")
      end
    end
  end

  context "when rule is pending" do
    let(:rule_status) { "pending" }

    context "when status is satisfied" do
      let(:status) { :satisfied }

      it "transitions rule to satisfied" do
        result

        expect(rule.reload.status).to eq("satisfied")
      end
    end

    context "when status is failed" do
      let(:status) { :failed }

      it "transitions rule to failed" do
        result

        expect(rule.reload.status).to eq("failed")
      end
    end

    context "when status is expired" do
      let(:status) { :expired }

      it "transitions rule to expired" do
        result

        expect(rule.reload.status).to eq("expired")
      end
    end
  end
end
