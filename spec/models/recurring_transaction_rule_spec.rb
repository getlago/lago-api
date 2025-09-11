# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringTransactionRule, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:wallet) }
    it { is_expected.to belong_to(:organization) }
  end

  describe "enums" do
    it "defines expected enum values" do
      expect(described_class.defined_enums).to include(
        "interval" => hash_including("weekly", "monthly", "quarterly", "yearly"),
        "method" => hash_including("fixed", "target"),
        "trigger" => hash_including("interval", "threshold"),
        "status" => hash_including("active", "terminated")
      )
    end
  end

  describe "scopes" do
    let!(:active_rule) { create(:recurring_transaction_rule, status: :active, expiration_at: nil) }
    let!(:future_rule) { create(:recurring_transaction_rule, status: :active, expiration_at: 1.day.from_now) }
    let!(:expired_rule) { create(:recurring_transaction_rule, status: :active, expiration_at: 1.day.ago) }
    let!(:terminated_rule) { create(:recurring_transaction_rule, status: :terminated, expiration_at: 1.day.ago) }

    it "returns correct records for active, eligible_for_termination, and expired scopes" do
      expect(described_class.active).to match_array([active_rule, future_rule])
      expect(described_class.eligible_for_termination).to match_array([expired_rule])
      expect(described_class.expired).to match_array([expired_rule, terminated_rule])
    end
  end

  describe "#mark_as_terminated!" do
    let(:recurring_transaction_rule) { create(:recurring_transaction_rule, status: :active) }

    it "marks the rule as terminated" do
      expect { recurring_transaction_rule.mark_as_terminated! }
        .to change(recurring_transaction_rule, :status)
        .from("active").to("terminated")
    end
  end

  describe "#apply_top_up_limits" do
    subject { rule.apply_top_up_limits(credit_amount:) }

    let(:rule) { create(:recurring_transaction_rule, wallet:, ignore_paid_top_up_limits:) }
    let(:wallet) { create(:wallet, paid_top_up_min_amount_cents: 10_00, paid_top_up_max_amount_cents: 20_00) }
    let(:credit_amount) { 5 }

    context "when recurring transaction rule ignores paid top up limits" do
      let(:ignore_paid_top_up_limits) { true }

      it "returns not changed value" do
        expect(subject).to eq credit_amount
      end
    end

    context "when recurring transaction rule does not ignore paid top up limits" do
      let(:ignore_paid_top_up_limits) { false }

      it "returns normalized to wallet limits value" do
        expect(subject).to eq 10
      end
    end
  end

  describe "#compute_granted_credits" do
    subject { rule.compute_granted_credits }

    let(:rule) { create(:recurring_transaction_rule, wallet:, ignore_paid_top_up_limits:) }
  end
end
