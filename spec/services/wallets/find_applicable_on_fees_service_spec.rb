# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::FindApplicableOnFeesService do
  describe ".call" do
    subject(:result) { described_class.call(allocation_rules:, fee:) }

    context "when there are applicable wallets for billable metrics, fee types and unrestricted" do
      let(:allocation_rules) do
        {
          bm_map: {
            SecureRandom.uuid => [SecureRandom.uuid, SecureRandom.uuid]
          },
          type_map: {
            "charge" => [SecureRandom.uuid, SecureRandom.uuid],
            "commitment" => [SecureRandom.uuid, SecureRandom.uuid]
          },
          unrestricted: [SecureRandom.uuid, SecureRandom.uuid]
        }
      end

      context "when fee matches by billable metric" do
        let(:fee) { create(:charge_fee) }
        let(:bm) { fee.charge.billable_metric }
        let(:matching_wallet_id) { allocation_rules[:bm_map][bm.id].first }

        before do
          allocation_rules[:bm_map][bm.id] = [SecureRandom.uuid, SecureRandom.uuid]
        end

        it "returns matching by billable metric wallet" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq matching_wallet_id
        end
      end

      context "when fee matches by fee type" do
        let(:fee) { create(:minimum_commitment_fee) }
        let(:matching_wallet_id) { allocation_rules[:type_map]["commitment"].first }

        it "returns matching by fee type wallet" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq matching_wallet_id
        end
      end

      context "when fee does not match by billable metric or fee type" do
        let(:fee) { create(:add_on_fee) }
        let(:matching_wallet_id) { allocation_rules[:unrestricted].first }

        it "returns unrestricted wallet" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq matching_wallet_id
        end
      end
    end

    context "when there are applicable wallets only for fee types and unrestricted" do
      let(:allocation_rules) do
        {
          bm_map: {},
          type_map: {
            "charge" => [SecureRandom.uuid, SecureRandom.uuid],
            "commitment" => [SecureRandom.uuid, SecureRandom.uuid]
          },
          unrestricted: [SecureRandom.uuid, SecureRandom.uuid]
        }
      end

      context "when fee matches by fee type" do
        let(:fee) { create(:minimum_commitment_fee) }
        let(:matching_wallet_id) { allocation_rules[:type_map]["commitment"].first }

        it "returns matching by fee type wallet" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq matching_wallet_id
        end
      end

      context "when fee does not match by fee type" do
        let(:fee) { create(:add_on_fee) }
        let(:matching_wallet_id) { allocation_rules[:unrestricted].first }

        it "returns unrestricted wallet" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq matching_wallet_id
        end
      end
    end

    context "when there are applicable wallets only for fee types" do
      let(:fee) { create(:fee, fee_type: "subscription") }

      let(:allocation_rules) do
        {
          bm_map: {},
          type_map: {
            "subscription" => [SecureRandom.uuid, SecureRandom.uuid],
            "charge" => [SecureRandom.uuid, SecureRandom.uuid]
          },
          unrestricted: []
        }
      end

      context "when fee matches by fee type" do
        let(:fee) { create(:fee, fee_type: "subscription") }
        let(:matching_wallet_id) { allocation_rules[:type_map]["subscription"].first }

        it "returns matching by fee type wallet" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq matching_wallet_id
        end
      end

      context "when fee does not match by fee type" do
        let(:fee) { create(:add_on_fee) }

        it "returns nil" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to be nil
        end
      end
    end

    context "when there are no applicable wallets" do
      let(:fee) { create(:fee) }

      let(:allocation_rules) do
        {
          bm_map: {},
          type_map: {},
          unrestricted: []
        }
      end

      it "returns nil" do
        expect(result).to be_success
        expect(result.top_priority_wallet).to be_nil
      end
    end

    context "when fee has wallet_id in grouped_by" do
      subject(:result) { described_class.call(allocation_rules:, fee:, wallets:) }

      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:wallet) { create(:wallet, customer:, status: :active) }
      let(:other_wallet) { create(:wallet, customer:, status: :active) }
      let(:wallets) { [wallet, other_wallet] }

      let(:allocation_rules) do
        {
          bm_map: {},
          type_map: {"charge" => [other_wallet.id]},
          unrestricted: [other_wallet.id]
        }
      end

      context "when wallet_id matches an existing wallet" do
        let(:fee) { create(:charge_fee, grouped_by: {"wallet_id" => wallet.id}) }

        it "returns the matching wallet" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq wallet.id
        end
      end

      context "when wallet_id does not match any wallet" do
        let(:fee) { create(:charge_fee, grouped_by: {"wallet_id" => SecureRandom.uuid}) }

        it "falls back to default allocation logic" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq other_wallet.id
        end
      end

      context "when wallets parameter is nil" do
        subject(:result) { described_class.call(allocation_rules:, fee:, wallets: nil) }

        let(:fee) { create(:charge_fee, grouped_by: {"wallet_id" => wallet.id}) }

        it "falls back to default allocation logic" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq other_wallet.id
        end
      end

      context "when fee has no wallet_id in grouped_by" do
        let(:fee) { create(:charge_fee, grouped_by: {"region" => "us-east"}) }

        it "uses default allocation logic" do
          expect(result).to be_success
          expect(result.top_priority_wallet).to eq other_wallet.id
        end
      end
    end
  end
end
