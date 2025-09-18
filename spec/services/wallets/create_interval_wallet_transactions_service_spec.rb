# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::CreateIntervalWalletTransactionsService do
  subject(:create_interval_transactions_service) { described_class.new }

  describe ".call" do
    let(:created_at) { DateTime.parse("20 Feb 2021") }
    let(:customer) { create(:customer) }
    let(:started_at) { nil }

    let(:wallet) do
      create(
        :wallet,
        customer:,
        created_at:,
        credits_ongoing_balance: 50,
        paid_top_up_min_amount_cents: 200_00
      )
    end

    let(:recurring_transaction_rule) do
      create(
        :recurring_transaction_rule,
        trigger: :interval,
        wallet:,
        interval:,
        created_at: created_at + 1.second,
        started_at:
      )
    end

    before { recurring_transaction_rule }

    def expect_to_have_scheduled_wallet_transaction(**attrs)
      expect(WalletTransactions::CreateJob).to have_been_enqueued
        .with(
          organization_id: customer.organization_id,
          params: {
            wallet_id: wallet.id,
            paid_credits: recurring_transaction_rule.paid_credits.to_s,
            granted_credits: recurring_transaction_rule.granted_credits.to_s,
            source: :interval,
            invoice_requires_successful_payment: false,
            metadata: [],
            name: "Recurring Transaction Rule"
          }.merge(attrs)
        )
    end

    context "when recurring transactions should be created weekly" do
      let(:interval) { :weekly }

      let(:current_date) do
        DateTime.parse("20 Jun 2022").prev_occurring(created_at.strftime("%A").downcase.to_sym)
      end

      it "enqueues a job on correct day" do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect_to_have_scheduled_wallet_transaction
        end
      end

      it "does not enqueue a job on other day" do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context "when recurring transaction rule has no transaction_name" do
        let(:recurring_transaction_rule) do
          create(
            :recurring_transaction_rule,
            trigger: :interval,
            wallet:,
            interval:,
            created_at: created_at + 1.second,
            started_at:,
            transaction_name: nil
          )
        end

        it "enqueues a job with transaction_name" do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction(name: nil)
          end
        end
      end

      context "when started_at is set on the transaction recurring rule" do
        let(:started_at) { DateTime.parse("20 Jun 2022") }

        it "does not enqueue a job one week after the creation date" do
          travel_to(current_date) do
            expect { create_interval_transactions_service.call }.not_to have_enqueued_job
          end
        end

        it "enqueues a job one week after the started_at date" do
          current_date = DateTime.parse("20 Jun 2022").next_occurring(started_at.strftime("%A").downcase.to_sym)

          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction
          end
        end
      end

      context "when method is target" do
        let(:recurring_transaction_rule) do
          create(
            :recurring_transaction_rule,
            trigger: :interval,
            wallet:,
            interval:,
            created_at: created_at + 1.second,
            method: "target",
            target_ongoing_balance: "200"
          )
        end

        it "calls wallet transaction create job with expected params" do
          travel_to(current_date) do
            create_interval_transactions_service.call
            expect_to_have_scheduled_wallet_transaction(
              paid_credits: "200.0", # the gap is 150 but wallet has min amount set to 200
              granted_credits: "0.0"
            )
          end
        end
      end
    end

    context "when recurring transactions should be created monthly" do
      let(:interval) { :monthly }
      let(:current_date) { created_at.next_month }

      it "enqueues a job on correct day" do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect_to_have_scheduled_wallet_transaction
        end
      end

      it "does not enqueue a job on other day" do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context "when wallet is created on a 31st" do
        let(:created_at) { DateTime.parse("31 Mar 2021") }
        let(:current_date) { DateTime.parse("30 Apr 2021") }

        it "enqueues a job if the month count less than 31 days" do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction
          end
        end
      end

      context "when started_at is set on the transaction recurring rule" do
        let(:created_at) { DateTime.parse("31 Mar 2025") }
        let(:started_at) { DateTime.parse("15 Apr 2025") }

        it "does not enqueue a job one month after the creation date" do
          current_date = DateTime.parse("30 Apr 2025")

          travel_to(current_date) do
            expect { create_interval_transactions_service.call }.not_to have_enqueued_job
          end
        end

        it "enqueues a job one month after the started_at date" do
          current_date = DateTime.parse("15 May 2025")

          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction
          end
        end
      end
    end

    context "when recurring transactions should be created quarterly" do
      let(:interval) { :quarterly }
      let(:current_date) { created_at + 3.months }

      it "enqueues a job on correct day" do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect_to_have_scheduled_wallet_transaction
        end
      end

      it "does not enqueue a job on other day" do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context "when it is March" do
        let(:created_at) { DateTime.parse("15 Mar 2021") }
        let(:current_date) { DateTime.parse("15 Sep 2022") }

        it "enqueues a job" do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction
          end
        end
      end

      context "when wallet is created on a 31st" do
        let(:created_at) { DateTime.parse("31 Mar 2021") }
        let(:current_date) { DateTime.parse("30 Jun 2022") }

        it "enqueues a job if the month count less than 31 days" do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction
          end
        end
      end
    end

    context "when recurring transactions should be created yearly" do
      let(:interval) { :yearly }
      let(:current_date) { created_at.next_year }

      it "enqueues a job on correct day" do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect_to_have_scheduled_wallet_transaction
        end
      end

      it "does not enqueue a job on other day" do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context "when wallet is created on 29th of february" do
        let(:created_at) { DateTime.parse("29 Feb 2020") }
        let(:current_date) { DateTime.parse("28 Feb 2022") }

        it "enqueues a job on 28th of february when year is not a leap year" do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction
          end
        end
      end
    end

    context "when on wallet creation day" do
      let(:interval) { :monthly }
      let(:customer) { create(:customer, timezone:) }
      let(:timezone) { nil }

      it "does not enqueue a job" do
        travel_to(created_at) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context "with customer timezone" do
        let(:timezone) { "Pacific/Noumea" }

        it "does not enqueue a job" do
          travel_to(created_at + 10.hours) do
            expect { create_interval_transactions_service.call }.not_to have_enqueued_job
          end
        end
      end
    end

    context "when wallet transactions had already been created that day" do
      let(:interval) { :monthly }
      let(:current_date) { DateTime.parse("20 Mar 2021T12:00:00") }

      let(:wallet_transaction) do
        create(
          :wallet_transaction,
          wallet:,
          transaction_type: :inbound,
          source: :interval,
          created_at: current_date - 1.hour
        )
      end

      before { wallet_transaction }

      it "does not enqueue a job" do
        travel_to(current_date) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context "with customer timezone" do
        let(:customer) { create(:customer, timezone:) }
        let(:timezone) { "Pacific/Noumea" }

        it "does not enqueue a job" do
          travel_to(current_date + 10.hours) do
            expect { create_interval_transactions_service.call }.not_to have_enqueued_job
          end
        end
      end
    end

    context "when rule requires successful payment" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          trigger: :interval,
          wallet:,
          interval:,
          created_at: created_at + 1.second,
          started_at:,
          invoice_requires_successful_payment: true
        )
      end
      let(:interval) { :weekly }

      let(:current_date) do
        DateTime.parse("20 Jun 2022").prev_occurring(created_at.strftime("%A").downcase.to_sym)
      end

      it "follows the rule configuration" do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect_to_have_scheduled_wallet_transaction(invoice_requires_successful_payment: true)
        end
      end
    end

    context "when rule have metadata" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          trigger: :interval,
          wallet:,
          interval:,
          created_at: created_at + 1.second,
          started_at:,
          transaction_metadata:
        )
      end
      let(:interval) { :weekly }

      let(:transaction_metadata) { [{"key" => "valid_value", "value" => "also_valid"}] }

      let(:current_date) do
        DateTime.parse("20 Jun 2022").prev_occurring(created_at.strftime("%A").downcase.to_sym)
      end

      it "enqueues a job with correct configuration" do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect_to_have_scheduled_wallet_transaction(metadata: transaction_metadata)
        end
      end
    end

    context "when rule has transaction_name" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          trigger: :interval,
          wallet:,
          interval:,
          created_at: created_at + 1.second,
          started_at:,
          transaction_name: "Monthly Credits Refill"
        )
      end
      let(:interval) { :weekly }

      let(:current_date) do
        DateTime.parse("20 Jun 2022").prev_occurring(created_at.strftime("%A").downcase.to_sym)
      end

      it "enqueues a job with the transaction name" do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect(WalletTransactions::CreateJob).to have_been_enqueued
            .with(
              organization_id: customer.organization_id,
              params: hash_including(name: "Monthly Credits Refill")
            )
        end
      end
    end

    context "when recurring transaction rule has expired" do
      let(:created_at) { DateTime.parse("20 Feb 2021") }
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          trigger: :interval,
          wallet:,
          interval:,
          created_at: created_at + 1.second,
          expiration_at: created_at + 2.hours,
          started_at:
        )
      end
      let(:interval) { :weekly }

      let(:current_date) do
        created_at + 2.weeks
      end

      it "does not enqueue a job for expired rules" do
        travel_to(current_date) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end
    end

    context "when credits are zero" do
      let(:created_at) { DateTime.parse("20 Feb 2021") }
      let(:wallet) { create(:wallet, customer:, created_at:) }
      let(:current_date) { created_at + 2.weeks }

      context "when both paid and granted credits are zero" do
        let(:recurring_transaction_rule) do
          create(
            :recurring_transaction_rule,
            trigger: :interval,
            wallet:,
            interval: :weekly,
            created_at:,
            method: "target",
            target_ongoing_balance: 500,
            granted_credits: 0
          )
        end

        before { wallet.update!(credits_ongoing_balance: 500) }

        it "does not enqueue a job" do
          travel_to(current_date) do
            expect { create_interval_transactions_service.call }.not_to have_enqueued_job
          end
        end
      end

      context "when only paid credits is zero" do
        let(:recurring_transaction_rule) do
          create(
            :recurring_transaction_rule,
            trigger: :interval,
            wallet:,
            interval: :weekly,
            created_at:,
            method: "fixed",
            target_ongoing_balance: 500,
            granted_credits: 100
          )
        end

        before { wallet.update!(credits_ongoing_balance: 1000) }

        it "enqueues a job" do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction
          end
        end
      end

      context "when only granted credits is zero" do
        let(:recurring_transaction_rule) do
          create(
            :recurring_transaction_rule,
            trigger: :interval,
            wallet:,
            interval: :weekly,
            created_at:,
            method: "target",
            paid_credits: 100,
            target_ongoing_balance: 500
          )
        end

        it "enqueues a job" do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction(paid_credits: "500.0", granted_credits: "0.0")
          end
        end
      end

      context "when both paid and granted credits are non-zero" do
        let(:recurring_transaction_rule) do
          create(
            :recurring_transaction_rule,
            trigger: :interval,
            wallet:,
            interval: :weekly,
            created_at:,
            method: "target",
            paid_credits: 100,
            granted_credits: 50,
            target_ongoing_balance: 500
          )
        end

        it "enqueues a job" do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect_to_have_scheduled_wallet_transaction(paid_credits: "500.0", granted_credits: "0.0")
          end
        end
      end
    end
  end
end
