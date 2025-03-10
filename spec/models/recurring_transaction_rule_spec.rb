# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringTransactionRule, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:wallet) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:interval).with_values(%i[weekly monthly quarterly yearly]) }
    it { is_expected.to define_enum_for(:method).with_values(%i[fixed target]) }
    it { is_expected.to define_enum_for(:trigger).with_values(%i[interval threshold]) }
    it { is_expected.to define_enum_for(:status).with_values(%i[active terminated]) }
  end

  describe "scopes" do
    let!(:active_rule) { create(:recurring_transaction_rule, status: :active, expiration_at: nil) }
    let!(:future_rule) { create(:recurring_transaction_rule, status: :active, expiration_at: 1.day.from_now) }
    let!(:expired_rule) { create(:recurring_transaction_rule, status: :active, expiration_at: 1.day.ago) }
    let!(:terminated_rule) { create(:recurring_transaction_rule, status: :terminated, expiration_at: 1.day.ago) }

    describe ".active" do
      it "returns active rules that are not expired" do
        expect(described_class.active).to contain_exactly(active_rule, future_rule)
      end
    end

    describe ".eligible_for_termination" do
      it "returns only active rules that have expired" do
        expect(described_class.eligible_for_termination).to contain_exactly(expired_rule)
      end
    end

    describe ".expired" do
      it "returns all rules that have expired" do
        expect(described_class.expired).to contain_exactly(expired_rule, terminated_rule)
      end
    end
  end

  describe "#mark_as_terminated!" do
    let(:recurring_transaction_rule) { create(:recurring_transaction_rule, status: :active) }

    it "marks the rule as terminated" do
      recurring_transaction_rule.mark_as_terminated!
      expect(recurring_transaction_rule).to be_terminated
    end
  end
end
