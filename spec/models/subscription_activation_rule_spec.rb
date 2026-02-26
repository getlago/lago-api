# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionActivationRule, type: :model do
  subject(:activation_rule) { build(:subscription_activation_rule) }

  describe "associations" do
    it do
      expect(activation_rule).to belong_to(:subscription)
      expect(activation_rule).to belong_to(:organization)
    end
  end

  describe "validations" do
    it do
      expect(activation_rule).to validate_presence_of(:rule_type)
      expect(activation_rule).to validate_inclusion_of(:rule_type).in_array(%w[payment_required])
      expect(activation_rule).to validate_presence_of(:status)
      expect(activation_rule).to validate_inclusion_of(:status).in_array(%w[pending satisfied failed not_applicable expired])
      expect(activation_rule).to validate_numericality_of(:timeout_hours).only_integer.is_greater_than(0).allow_nil
    end
  end

  describe "scopes" do
    describe ".pending" do
      let!(:pending_rule) { create(:subscription_activation_rule, status: "pending") }

      before { create(:subscription_activation_rule, :satisfied) }

      it "returns only pending rules" do
        expect(described_class.pending).to eq([pending_rule])
      end
    end

    describe ".failed" do
      let!(:failed_rule) { create(:subscription_activation_rule, :failed) }

      before { create(:subscription_activation_rule, status: "pending") }

      it "returns only failed rules" do
        expect(described_class.failed).to eq([failed_rule])
      end
    end

    describe ".satisfied" do
      let!(:satisfied_rule) { create(:subscription_activation_rule, :satisfied) }

      before { create(:subscription_activation_rule, status: "pending") }

      it "returns only satisfied rules" do
        expect(described_class.satisfied).to eq([satisfied_rule])
      end
    end
  end
end
