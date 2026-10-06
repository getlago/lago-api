# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260805104301_add_alerts_code_unique_per_wallet_index")

RSpec.describe AddAlertsCodeUniquePerWalletIndex do
  describe "#rename_codes_already_taken_on_the_same_wallet" do
    subject(:rename) do
      verbose = ActiveRecord::Migration.verbose
      ActiveRecord::Migration.verbose = false
      described_class.new.send(:rename_codes_already_taken_on_the_same_wallet)
    ensure
      ActiveRecord::Migration.verbose = verbose
    end

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
