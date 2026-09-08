# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::ThresholdTopUpService do
  subject(:top_up_service) { described_class.new(wallet:) }

  let(:paid_top_up_min_amount_cents) { 205_50 }
  let(:paid_top_up_max_amount_cents) { nil }
  let(:wallet) do
    create(
      :wallet,
      balance_cents: 1000,
      ongoing_balance_cents: 550,
      ongoing_usage_balance_cents: 450,
      credits_balance: 10.0,
      credits_ongoing_balance: 5.5,
      credits_ongoing_usage_balance: 4.0,
      paid_top_up_min_amount_cents:,
      paid_top_up_max_amount_cents:
    )
  end

  describe "#call" do
    let(:recurring_transaction_rule) do
      create(
        :recurring_transaction_rule,
        wallet:,
        trigger: "threshold",
        threshold_credits: "6.0",
        paid_credits: "10.0",
        granted_credits: "3.0",
        ignore_paid_top_up_limits: true
      )
    end

    before { recurring_transaction_rule }

    it "calls wallet transaction create job with expected params" do
      expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        .with(
          organization_id: wallet.organization.id,
          params: {
            wallet_id: wallet.id,
            paid_credits: "10.0",
            granted_credits: "3.0",
            source: :threshold,
            invoice_requires_successful_payment: false,
            metadata: [],
            name: "Recurring Transaction Rule",
            ignore_paid_top_up_limits: true,
            purchase_order_number: nil
          },
          unique_transaction: true
        )
    end

    context "when rule requires successful payment" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          paid_credits: "10.0",
          granted_credits: "3.0",
          invoice_requires_successful_payment: true
        )
      end

      it "calls wallet transaction create job with expected params" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(invoice_requires_successful_payment: true),
            unique_transaction: true
          )
      end
    end

    context "when the rule keeps the wallet top-up limits" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          paid_credits: "10.0",
          granted_credits: "3.0",
          ignore_paid_top_up_limits: false
        )
      end

      it "enqueues the top-up with the limit check enabled" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(ignore_paid_top_up_limits: false),
            unique_transaction: true
          )
      end
    end

    context "when rule contains transaction metadata" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          paid_credits: "10.0",
          granted_credits: "3.0",
          transaction_metadata:
        )
      end

      let(:transaction_metadata) { [{"key" => "valid_value", "value" => "also_valid"}] }

      it "calls wallet transaction create job with expected params" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(metadata: transaction_metadata),
            unique_transaction: true
          )
      end
    end

    context "when rule has invoice custom sections" do
      let(:invoice_custom_section) { create(:invoice_custom_section, organization: wallet.organization) }

      before do
        create(:recurring_rule_applied_invoice_custom_section,
          recurring_transaction_rule:,
          invoice_custom_section:)
      end

      it "forwards invoice_custom_section params to the job" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(
              invoice_custom_section: {
                skip_invoice_custom_sections: false,
                invoice_custom_section_ids: [invoice_custom_section.id]
              }
            ),
            unique_transaction: true
          )
      end
    end

    context "when rule has skip_invoice_custom_sections" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          paid_credits: "10.0",
          granted_credits: "3.0",
          skip_invoice_custom_sections: true
        )
      end

      it "forwards the skip flag to the job without fallback to other sections" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(
              invoice_custom_section: {
                skip_invoice_custom_sections: true,
                invoice_custom_section_ids: []
              }
            ),
            unique_transaction: true
          )
      end
    end

    context "when rule does not contain transaction_name" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          paid_credits: "10.0",
          granted_credits: "3.0",
          transaction_name: nil
        )
      end

      it "calls wallet transaction create job with the transaction name" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(name: nil),
            unique_transaction: true
          )
      end
    end

    context "when rule has purchase_order_number" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          paid_credits: "10.0",
          granted_credits: "3.0",
          purchase_order_number: "PO-RULE-123"
        )
      end

      it "calls wallet transaction create job with the rule purchase order number" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(purchase_order_number: "PO-RULE-123"),
            unique_transaction: true
          )
      end
    end

    context "when rule purchase_order_number is blank and wallet has purchase_order_number" do
      let(:wallet) do
        create(
          :wallet,
          balance_cents: 1000,
          ongoing_balance_cents: 550,
          ongoing_usage_balance_cents: 450,
          credits_balance: 10.0,
          credits_ongoing_balance: 5.5,
          credits_ongoing_usage_balance: 4.0,
          paid_top_up_min_amount_cents: 205_50,
          purchase_order_number: "PO-WALLET-123"
        )
      end
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          paid_credits: "10.0",
          granted_credits: "3.0",
          purchase_order_number: "   "
        )
      end

      it "calls wallet transaction create job with the wallet purchase order number" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(purchase_order_number: "PO-WALLET-123"),
            unique_transaction: true
          )
      end
    end

    context "when neither rule nor wallet has purchase_order_number" do
      it "calls wallet transaction create job without purchase order number" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(purchase_order_number: nil),
            unique_transaction: true
          )
      end
    end

    context "when the wallet is several top-ups short" do
      let(:wallet) do
        create(
          :wallet,
          balance_cents: 5000,
          ongoing_balance_cents: -42_980,
          ongoing_usage_balance_cents: 47_980,
          credits_balance: 50.0,
          credits_ongoing_balance: -429.8,
          credits_ongoing_usage_balance: 479.8,
          rate_amount: 1.0
        )
      end

      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "10.0",
          paid_credits: "50.0",
          granted_credits: "0.0"
        )
      end

      it "closes the whole gap in a single top-up" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(paid_credits: "450.0", granted_credits: "0.0"),
            unique_transaction: true
          )
      end
    end

    context "when border has NOT been crossed" do
      let(:recurring_transaction_rule) do
        create(:recurring_transaction_rule, wallet:, trigger: "threshold", threshold_credits: "2.0")
      end

      it "does not call wallet transaction create job" do
        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end
    end

    context "when the ongoing balance write changed nothing" do
      subject(:top_up_service) { described_class.new(wallet:, state_changed: false) }

      it "does not call wallet transaction create job" do
        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end
    end

    context "with pending transactions" do
      it "does not call wallet transaction create job" do
        create(:wallet_transaction, wallet:, amount: 1.0, credit_amount: 1.0, status: "pending")

        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end

      context "when the wallet rate is not one" do
        let(:wallet) do
          create(
            :wallet,
            balance_cents: 1000,
            ongoing_balance_cents: 550,
            ongoing_usage_balance_cents: 450,
            credits_balance: 10.0,
            credits_ongoing_balance: 5.5,
            credits_ongoing_usage_balance: 4.0,
            rate_amount: 0.1,
            paid_top_up_min_amount_cents: 205_50
          )
        end

        it "counts the pending credits rather than the pending currency amount" do
          create(:wallet_transaction, wallet:, amount: 0.1, credit_amount: 1.0, status: "pending")

          expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end
    end

    context "when recurring_transaction_rule is expired" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          method: "target",
          target_ongoing_balance: "200",
          expiration_at: 1.day.ago
        )
      end

      it "does not call wallet transaction create job" do
        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end
    end

    context "when method is target" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          method: "target",
          target_ongoing_balance: "200"
        )
      end

      it "calls wallet transaction create job with expected params" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: {
              wallet_id: wallet.id,
              paid_credits: "205.5", # the gap is 194.5 but min transaction is 205.5
              granted_credits: "0.0",
              source: :threshold,
              invoice_requires_successful_payment: false,
              metadata: [],
              name: "Recurring Transaction Rule",
              ignore_paid_top_up_limits: true,
              purchase_order_number: nil
            },
            unique_transaction: true
          )
      end

      context "when the refill exceeds the wallet max top-up limit" do
        let(:paid_top_up_min_amount_cents) { nil }
        let(:paid_top_up_max_amount_cents) { 100_00 }

        it "enqueues the full refill with the limit check disabled" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
            .with(
              organization_id: wallet.organization.id,
              params: hash_including(
                paid_credits: "194.5",
                ignore_paid_top_up_limits: true
              ),
              unique_transaction: true
            )
        end
      end

      context "when grants_target_top_up is true" do
        let(:recurring_transaction_rule) do
          create(
            :recurring_transaction_rule,
            wallet:,
            trigger: "threshold",
            threshold_credits: "6.0",
            method: "target",
            target_ongoing_balance: "200",
            grants_target_top_up: true
          )
        end

        it "enqueues the raw gap as granted credits, bypassing the paid_top_up_min limit" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
            .with(
              organization_id: wallet.organization.id,
              params: hash_including(
                paid_credits: "0.0",
                granted_credits: "194.5"
              ),
              unique_transaction: true
            )
        end
      end
    end

    describe "declined top-ups" do
      let(:failed_top_up) do
        create(:wallet_transaction, :failed, wallet:, source: :threshold, failed_at: 10.minutes.ago)
      end

      before { failed_top_up }

      it "does not call wallet transaction create job while the failure is recent" do
        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end

      context "when the failure is older than the back-off window" do
        let(:failed_top_up) do
          create(
            :wallet_transaction,
            :failed,
            wallet:,
            source: :threshold,
            failed_at: described_class::DECLINE_BACKOFF.ago - 1.minute
          )
        end

        it "calls wallet transaction create job" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end

      context "when a top-up settled after the failure" do
        before { create(:wallet_transaction, wallet:, source: :threshold, created_at: 1.minute.ago) }

        it "calls wallet transaction create job" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end

      context "when only granted credits arrived after the failure" do
        before do
          create(
            :wallet_transaction,
            wallet:,
            source: :threshold,
            transaction_status: :granted,
            settled_at: 1.minute.ago
          )
        end

        it "does not call wallet transaction create job" do
          expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end

      context "when a top-up created before the failure settled after it" do
        before do
          create(
            :wallet_transaction,
            wallet:,
            source: :manual,
            created_at: 2.hours.ago,
            settled_at: 1.minute.ago
          )
        end

        it "calls wallet transaction create job" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end

      context "when the rule only grants credits" do
        let(:recurring_transaction_rule) do
          create(
            :recurring_transaction_rule,
            wallet:,
            trigger: "threshold",
            threshold_credits: "6.0",
            paid_credits: "0.0",
            granted_credits: "3.0"
          )
        end

        it "calls wallet transaction create job" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end

      context "when the failed transaction was not an automatic top-up" do
        let(:failed_top_up) do
          create(:wallet_transaction, :failed, wallet:, source: :manual, failed_at: 10.minutes.ago)
        end

        it "calls wallet transaction create job" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end
    end

    # Reporting only. Refusing a top-up would leave the wallet short, and the allocator
    # routes all of a customer's usage into a threshold wallet on the assumption that its
    # rule always refills it.
    describe "runaway top-ups", :sentry do
      shared_examples "no burst is reported" do
        it "tops up" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        end

        it "reports nothing" do
          top_up_service.call

          expect(sentry_events).to be_empty
        end
      end

      context "when the wallet topped up fewer times than the burst threshold" do
        before { create_list(:wallet_transaction, described_class::BURST_TOP_UPS - 1, wallet:, source: :threshold) }

        it_behaves_like "no burst is reported"
      end

      context "when the top-ups are older than the window" do
        before do
          create_list(
            :wallet_transaction,
            described_class::BURST_TOP_UPS,
            wallet:,
            source: :threshold,
            created_at: described_class::BURST_WINDOW.ago - 1.minute
          )
        end

        it_behaves_like "no burst is reported"
      end

      context "when the earlier transactions were not automatic top-ups" do
        before { create_list(:wallet_transaction, described_class::BURST_TOP_UPS, wallet:, source: :manual) }

        it_behaves_like "no burst is reported"
      end

      context "when the earlier top-ups only moved credits out" do
        before do
          create_list(
            :wallet_transaction,
            described_class::BURST_TOP_UPS,
            wallet:,
            source: :threshold,
            transaction_type: :outbound
          )
        end

        it_behaves_like "no burst is reported"
      end

      # One top-up writes a second row when the rule also grants credits. Only the
      # purchased row is a charge, so only that one counts.
      context "when the earlier top-ups also granted credits" do
        before do
          create_list(:wallet_transaction, described_class::BURST_TOP_UPS - 1, wallet:, source: :threshold)
          create_list(
            :wallet_transaction,
            described_class::BURST_TOP_UPS,
            wallet:,
            source: :threshold,
            transaction_status: :granted
          )
        end

        it_behaves_like "no burst is reported"
      end

      context "when the wallet topped up repeatedly in the last few minutes" do
        before { create_list(:wallet_transaction, described_class::BURST_TOP_UPS, wallet:, source: :threshold) }

        it "still tops up, because the shortfall is real" do
          expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        end

        it "reports the burst, so a person hears about it" do
          top_up_service.call

          expect(sentry_events.map(&:message)).to eq(["Automatic wallet top-up burst"])
        end
      end
    end
  end
end
