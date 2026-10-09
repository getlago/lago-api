# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260805104301_add_alerts_code_unique_per_wallet_index")

RSpec.describe AddAlertsCodeUniquePerWalletIndex::DuplicateCodeRename do
  describe "#call" do
    subject(:rename) { described_class.new.call }

    let(:organization) { create(:organization) }
    let(:wallet) { create(:wallet, organization:) }
    let(:other_wallet) { create(:wallet, organization:) }

    let(:earliest) do
      create(:wallet_balance_amount_alert, organization:, wallet:, code: "low", thresholds: nil, created_at: 2.days.ago)
    end

    let(:later) do
      create(:wallet_credits_balance_alert, organization:, wallet:, code: "low", thresholds: nil, created_at: 1.day.ago)
    end

    before do
      # The index rejects the duplicates the rename handles. DDL is transactional, so the drop is rolled back.
      ActiveRecord::Base.connection.execute("DROP INDEX idx_alerts_code_unique_per_wallet")
    end

    context "with two alerts of different types sharing a code on the same wallet" do
      before do
        earliest
        later
      end

      it "keeps the code of the earliest one and suffixes the later one with its type" do
        rename

        expect(earliest.reload.code).to eq("low")
        expect(later.reload.code).to eq("low-wallet_credits_balance")
      end

      it "returns the renamed alert with its wallet and both codes" do
        expect(rename).to eq([
          {"wallet_id" => wallet.id, "wallet_code" => wallet.code, "old_code" => "low", "new_code" => "low-wallet_credits_balance"}
        ])
      end
    end

    context "when the type suffixed code is already taken on the wallet" do
      let!(:taken) do
        create(
          :wallet_ongoing_balance_amount_alert,
          organization:,
          wallet:,
          code: "low-wallet_credits_balance",
          thresholds: nil,
          created_at: 3.days.ago
        )
      end

      before do
        earliest
        later
      end

      it "suffixes the later one with its id" do
        rename

        expect(earliest.reload.code).to eq("low")
        expect(later.reload.code).to eq("low-#{later.id}")
        expect(taken.reload.code).to eq("low-wallet_credits_balance")
      end
    end

    context "with a soft-deleted alert holding the code" do
      let!(:deleted) do
        create(
          :wallet_credits_balance_alert,
          organization:,
          wallet:,
          code: "low",
          thresholds: nil,
          created_at: 3.days.ago,
          deleted_at: 1.day.ago
        )
      end

      before { earliest }

      it "neither renames it nor counts it as a duplicate" do
        rename

        expect(earliest.reload.code).to eq("low")
        expect(UsageMonitoring::Alert.with_discarded.find(deleted.id).code).to eq("low")
      end
    end

    context "with three alerts of different types sharing a code on the same wallet" do
      let!(:latest) do
        create(:wallet_ongoing_balance_amount_alert, organization:, wallet:, code: "low", thresholds: nil, created_at: 1.hour.ago)
      end

      before do
        earliest
        later
      end

      it "keeps the earliest code and suffixes each later one with its own type" do
        rename

        expect(earliest.reload.code).to eq("low")
        expect(later.reload.code).to eq("low-wallet_credits_balance")
        expect(latest.reload.code).to eq("low-wallet_ongoing_balance_amount")
      end
    end

    context "with two alerts sharing a code and created at the same time" do
      let(:created_at) { 1.day.ago }
      let(:ids) { Array.new(2) { SecureRandom.uuid }.sort }

      let!(:first_by_id) do
        create(:wallet_credits_balance_alert, id: ids.first, organization:, wallet:, code: "low", thresholds: nil, created_at:)
      end

      let!(:second_by_id) do
        create(:wallet_balance_amount_alert, id: ids.last, organization:, wallet:, code: "low", thresholds: nil, created_at:)
      end

      it "keeps the code of the one with the lowest id" do
        rename

        expect(first_by_id.reload.code).to eq("low")
        expect(second_by_id.reload.code).to eq("low-wallet_balance_amount")
      end
    end

    context "when the type suffixed code is only held by a soft-deleted alert" do
      let!(:deleted) do
        create(
          :wallet_ongoing_balance_amount_alert,
          organization:,
          wallet:,
          code: "low-wallet_credits_balance",
          thresholds: nil,
          created_at: 3.days.ago,
          deleted_at: 1.day.ago
        )
      end

      before do
        earliest
        later
      end

      it "still suffixes the later one with its type" do
        rename

        expect(later.reload.code).to eq("low-wallet_credits_balance")
        expect(UsageMonitoring::Alert.with_discarded.find(deleted.id).code).to eq("low-wallet_credits_balance")
      end
    end

    context "when the type suffixed code is only held on another wallet" do
      let!(:elsewhere) do
        create(
          :wallet_credits_balance_alert,
          organization:,
          wallet: other_wallet,
          code: "low-wallet_credits_balance",
          thresholds: nil,
          created_at: 3.days.ago
        )
      end

      before do
        earliest
        later
      end

      it "still suffixes the later one with its type" do
        rename

        expect(later.reload.code).to eq("low-wallet_credits_balance")
        expect(elsewhere.reload.code).to eq("low-wallet_credits_balance")
      end
    end

    context "with duplicates on two wallets" do
      let!(:other_earliest) do
        create(:wallet_balance_amount_alert, organization:, wallet: other_wallet, code: "low", thresholds: nil, created_at: 2.days.ago)
      end

      let!(:other_later) do
        create(:wallet_credits_balance_alert, organization:, wallet: other_wallet, code: "low", thresholds: nil, created_at: 1.day.ago)
      end

      before do
        earliest
        later
      end

      it "renames the later duplicate on each wallet" do
        rename

        expect([earliest, later, other_earliest, other_later].map { it.reload.code })
          .to eq(%w[low low-wallet_credits_balance low low-wallet_credits_balance])
      end
    end

    context "with subscription alerts sharing a code" do
      let!(:subscription_alerts) do
        create_list(:usage_current_amount_alert, 2, organization:, code: "low", thresholds: nil)
      end

      before { earliest }

      it "leaves them unchanged" do
        rename

        expect(subscription_alerts.map { it.reload.code }).to eq(%w[low low])
        expect(earliest.reload.code).to eq("low")
      end
    end

    context "without any duplicate" do
      before do
        earliest
        create(:wallet_credits_balance_alert, organization:, wallet:, code: "high", thresholds: nil)
      end

      it "renames nothing" do
        expect { rename }.not_to change { UsageMonitoring::Alert.order(:code).pluck(:code) }
      end
    end

    context "with an alert holding the code on another wallet" do
      let!(:other) do
        create(:wallet_credits_balance_alert, organization:, wallet: other_wallet, code: "low", thresholds: nil, created_at: 3.days.ago)
      end

      before { earliest }

      it "leaves both codes unchanged" do
        rename

        expect(earliest.reload.code).to eq("low")
        expect(other.reload.code).to eq("low")
      end
    end
  end
end
