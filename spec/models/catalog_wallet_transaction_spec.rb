# frozen_string_literal: true

require "rails_helper"

describe CatalogWalletTransaction do
  subject(:transaction) { build(:catalog_wallet_transaction) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(transaction).to define_enum_for(:direction)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(inbound: "inbound", outbound: "outbound")
      expect(transaction).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(pending: "pending", settled: "settled", failed: "failed")
      expect(transaction).to define_enum_for(:reason)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(
          top_up: "top_up",
          credit_allocation: "credit_allocation",
          invoice_void: "invoice_void",
          invoice_application: "invoice_application",
          void: "void"
        )
      expect(transaction).to define_enum_for(:allocation_type)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(billing_cycle: "billing_cycle", ongoing_balance: "ongoing_balance")
        .with_prefix
    end
  end

  describe "associations" do
    it do
      expect(transaction).to belong_to(:organization)
      expect(transaction).to belong_to(:catalog_wallet)
      expect(transaction).to belong_to(:credit_allocation).class_name("CatalogWalletCreditAllocation").optional
      expect(transaction).to belong_to(:invoice).optional
    end
  end

  describe "Scopes" do
    describe ".spendable" do
      let(:catalog_wallet) { create(:catalog_wallet) }
      let(:spendable) { create(:catalog_wallet_transaction, catalog_wallet:) }

      before do
        spendable
        create(:catalog_wallet_transaction, :pending, catalog_wallet:)
        create(:catalog_wallet_transaction, :failed, catalog_wallet:)
        create(:catalog_wallet_transaction, catalog_wallet:, remaining_credit_amount_cents: 0)
        create(:catalog_wallet_transaction, :invoice_application, catalog_wallet:)
      end

      it "returns the settled inbound entries with credit left" do
        expect(catalog_wallet.transactions.spendable).to eq([spendable])
      end
    end

    describe ".in_spending_order" do
      let(:catalog_wallet) { create(:catalog_wallet) }
      let(:bought) { create(:catalog_wallet_transaction, catalog_wallet:, purchase_amount_cents: 8_000, created_at: 3.days.ago) }
      let(:free) { create(:catalog_wallet_transaction, catalog_wallet:, created_at: 2.days.ago) }
      let(:first_priority) { create(:catalog_wallet_transaction, catalog_wallet:, priority: 10, purchase_amount_cents: 8_000) }
      let(:newer_free) { create(:catalog_wallet_transaction, catalog_wallet:, created_at: 1.day.ago) }

      it "orders by priority, then free credit before bought credit, then oldest first" do
        expect(catalog_wallet.transactions.in_spending_order).to eq([first_priority, free, newer_free, bought])
      end

      context "when joined with the credit allocation" do
        let(:grant) { create(:catalog_wallet_transaction, :billing_cycle_grant, catalog_wallet:) }

        it "orders by the entry's own purchase amount" do
          expect(catalog_wallet.transactions.joins(:credit_allocation).in_spending_order).to eq([grant])
        end
      end
    end
  end

  describe "validations" do
    it do
      expect(transaction).to validate_inclusion_of(:priority).in_range(1..50)
      expect(transaction).to validate_numericality_of(:credit_amount_cents).only_integer.is_greater_than(0)
      expect(transaction).to validate_numericality_of(:purchase_amount_cents).only_integer.is_greater_than_or_equal_to(0).allow_nil
      expect(build(:catalog_wallet_transaction, :billing_cycle_grant)).to be_valid
      expect(build(:catalog_wallet_transaction, :invoice_application)).to be_valid
    end

    describe "remaining credit validation" do
      it { is_expected.to validate_numericality_of(:remaining_credit_amount_cents).only_integer.is_greater_than_or_equal_to(0).allow_nil }

      it "rejects more than the credit amount" do
        transaction = build(:catalog_wallet_transaction, remaining_credit_amount_cents: 10_001)

        expect(transaction.tap(&:valid?).errors.where(:remaining_credit_amount_cents, :less_than_or_equal_to)).to be_present
      end
    end
  end

  describe "database constraints" do
    def save_unvalidated(*traits, **attributes)
      build(:catalog_wallet_transaction, *traits, **attributes).save!(validate: false)
    end

    it "refuses a remaining credit below zero" do
      expect { save_unvalidated(remaining_credit_amount_cents: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_transactions_remaining_non_negative/)
    end

    it "refuses a remaining credit above the credit amount" do
      expect { save_unvalidated(remaining_credit_amount_cents: 10_001) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_transactions_remaining_within_credit/)
    end

    it "refuses an allocation type on an entry that no rule made" do
      expect { save_unvalidated(allocation_type: "ongoing_balance") }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_transactions_allocation_fields/)
    end

    it "refuses a remaining credit on an outbound entry" do
      expect { save_unvalidated(:invoice_application, remaining_credit_amount_cents: 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_transactions_direction_fields/)
    end

    it "refuses a failed entry without a failure date" do
      expect { save_unvalidated(:failed, failed_at: nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_transactions_failed_at_with_status/)
    end

    it "refuses a failure date on an entry that did not fail" do
      expect { save_unvalidated(failed_at: Time.current) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_transactions_failed_at_with_status/)
    end

    it "accepts a failed entry with its failure date" do
      expect(create(:catalog_wallet_transaction, :failed)).to be_persisted
    end

    it "refuses a second grant for the same rule and cycle" do
      grant = create(:catalog_wallet_transaction, :billing_cycle_grant)

      expect { save_unvalidated(:billing_cycle_grant, catalog_wallet: grant.catalog_wallet, credit_allocation: grant.credit_allocation) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_catalog_wallet_transactions_on_grant_occurrence/)
    end

    it "refuses a second pending ongoing-balance purchase on the wallet" do
      rule = create(:catalog_wallet_credit_allocation, :ongoing_balance)
      attributes = {catalog_wallet: rule.catalog_wallet, credit_allocation: rule, reason: "credit_allocation", allocation_type: "ongoing_balance"}
      create(:catalog_wallet_transaction, :pending, **attributes)

      expect { save_unvalidated(:pending, **attributes) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_catalog_wallet_transactions_one_pending_ongoing_balance/)
    end

    it "refuses an idempotency key already used on the wallet" do
      existing = create(:catalog_wallet_transaction, idempotency_key: "top-up-1")

      expect { save_unvalidated(catalog_wallet: existing.catalog_wallet, idempotency_key: "top-up-1") }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_catalog_wallet_transactions_on_wallet_and_idempotency_key/)
    end
  end
end
