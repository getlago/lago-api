# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransaction do
  describe "validations" do
    it { is_expected.to validate_presence_of(:priority) }
    it { is_expected.to validate_inclusion_of(:priority).in_range(1..50) }
    it { is_expected.to validate_length_of(:name).is_at_most(255).is_at_least(1).allow_nil }
    it { is_expected.to validate_exclusion_of(:invoice_requires_successful_payment).in_array([nil]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:wallet) }
    it { is_expected.to belong_to(:invoice).optional }
    it { is_expected.to belong_to(:credit_note).optional }
    it { is_expected.to belong_to(:organization) }
  end

  describe "enums" do
    it "defines expected enum values" do
      expect(described_class.defined_enums).to include(
        "status" => hash_including("pending", "settled", "failed"),
        "transaction_status" => hash_including("purchased", "granted", "voided", "invoiced"),
        "transaction_type" => hash_including("inbound", "outbound"),
        "source" => hash_including("manual", "interval", "threshold")
      )
    end
  end

  describe ".order_by_priority" do
    subject { described_class.order_by_priority }

    let(:wallet) { create(:wallet) }
    let!(:purchased_10) { create(:wallet_transaction, wallet:, priority: 10, transaction_status: :purchased, created_at: 3.days.ago) }
    let!(:granted_5) { create(:wallet_transaction, wallet:, priority: 5, transaction_status: :granted, created_at: 2.days.ago) }
    let!(:granted_10) { create(:wallet_transaction, wallet:, priority: 10, transaction_status: :granted, created_at: 1.day.ago) }
    let!(:voided_5) { create(:wallet_transaction, wallet:, priority: 5, transaction_status: :voided, created_at: 4.days.ago) }
    let!(:invoiced_15) { create(:wallet_transaction, wallet:, priority: 15, transaction_status: :invoiced, created_at: 5.days.ago) }
    let!(:granted_10_older) { create(:wallet_transaction, wallet:, priority: 10, transaction_status: :granted, created_at: 2.days.ago) }

    it "orders by priority first, then by transaction_status, then by created_at" do
      expect(subject.to_a).to eq([
        granted_5,
        voided_5,
        granted_10_older, # priority 10, granted, 2 days ago
        granted_10, # priority 10, granted, 1 day ago
        purchased_10,
        invoiced_15
      ])
    end
  end

  describe "#mark_as_failed!" do
    let(:transaction) { create(:wallet_transaction, status: :pending) }

    it "marks the transaction as failed" do
      expect { transaction.mark_as_failed! }
        .to change(transaction, :status).from("pending").to("failed")
        .and change(transaction, :failed_at).from(nil)
    end
  end
end
