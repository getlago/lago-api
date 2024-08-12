# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::CreateIntervalWalletTransactionsService, type: :service do
  subject(:create_interval_transactions_service) { described_class.new }

  describe '.call' do
    let(:wallet) { create(:wallet, customer:, created_at:, credits_ongoing_balance: 50) }
    let(:created_at) { DateTime.parse('20 Feb 2021') }
    let(:customer) { create(:customer) }
    let(:started_at) { nil }

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

    context 'when recurring transactions should be created weekly' do
      let(:interval) { :weekly }

      let(:current_date) do
        DateTime.parse('20 Jun 2022').prev_occurring(created_at.strftime('%A').downcase.to_sym)
      end

      it 'enqueues a job on correct day' do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect(WalletTransactions::CreateJob).to have_been_enqueued
            .with(
              organization_id: customer.organization_id,
              params: {
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
                invoice_requires_successful_payment: false,
                metadata: {}
              }
            )
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context "when started_at is set on the transaction recurring rule" do
        let(:started_at) { DateTime.parse("20 Jun 2022") }

        it "does not enqueue a job one week after the creation date" do
          travel_to(current_date) do
            expect { create_interval_transactions_service.call }.not_to have_enqueued_job
          end
        end

        it 'enqueues a job one week after the started_at date' do
          current_date = DateTime.parse('20 Jun 2022').next_occurring(started_at.strftime('%A').downcase.to_sym)

          travel_to(current_date) do
            create_interval_transactions_service.call

            expect(WalletTransactions::CreateJob).to have_been_enqueued
              .with(
                organization_id: customer.organization_id,
                params: {
                  wallet_id: wallet.id,
                  paid_credits: recurring_transaction_rule.paid_credits.to_s,
                  granted_credits: recurring_transaction_rule.granted_credits.to_s,
                  source: :interval,
                  invoice_requires_successful_payment: false,
                  metadata: {}
                }
              )
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
            expect { create_interval_transactions_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
              .with(
                organization_id: wallet.organization.id,
                params: {
                  wallet_id: wallet.id,
                  paid_credits: "150.0",
                  granted_credits: "0.0",
                  source: :interval,
                  invoice_requires_successful_payment: false,
                  metadata: {}
                }
              )
          end
        end
      end
    end

    context 'when recurring transactions should be created monthly' do
      let(:interval) { :monthly }
      let(:current_date) { created_at.next_month }

      it 'enqueues a job on correct day' do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect(WalletTransactions::CreateJob).to have_been_enqueued
            .with(
              organization_id: customer.organization_id,
              params: {
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
                invoice_requires_successful_payment: false,
                metadata: {}
              }
            )
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context 'when wallet is created on a 31st' do
        let(:created_at) { DateTime.parse('31 Mar 2021') }
        let(:current_date) { DateTime.parse('30 Apr 2021') }

        it 'enqueues a job if the month count less than 31 days' do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect(WalletTransactions::CreateJob).to have_been_enqueued
              .with(
                organization_id: customer.organization_id,
                params: {
                  wallet_id: wallet.id,
                  paid_credits: recurring_transaction_rule.paid_credits.to_s,
                  granted_credits: recurring_transaction_rule.granted_credits.to_s,
                  source: :interval,
                  invoice_requires_successful_payment: false,
                  metadata: {}
                }
              )
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

        it 'enqueues a job one month after the started_at date' do
          current_date = DateTime.parse("15 May 2025")

          travel_to(current_date) do
            create_interval_transactions_service.call

            expect(WalletTransactions::CreateJob).to have_been_enqueued
              .with(
                organization_id: customer.organization_id,
                params: {
                  wallet_id: wallet.id,
                  paid_credits: recurring_transaction_rule.paid_credits.to_s,
                  granted_credits: recurring_transaction_rule.granted_credits.to_s,
                  source: :interval,
                  invoice_requires_successful_payment: false,
                  metadata: {}
                }
              )
          end
        end
      end
    end

    context 'when recurring transactions should be created quarterly' do
      let(:interval) { :quarterly }
      let(:current_date) { created_at + 3.months }

      it 'enqueues a job on correct day' do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect(WalletTransactions::CreateJob).to have_been_enqueued
            .with(
              organization_id: customer.organization_id,
              params: {
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
                invoice_requires_successful_payment: false,
                metadata: {}
              }
            )
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context 'when it is March' do
        let(:created_at) { DateTime.parse('15 Mar 2021') }
        let(:current_date) { DateTime.parse('15 Sep 2022') }

        it 'enqueues a job' do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect(WalletTransactions::CreateJob).to have_been_enqueued
              .with(
                organization_id: customer.organization_id,
                params: {
                  wallet_id: wallet.id,
                  paid_credits: recurring_transaction_rule.paid_credits.to_s,
                  granted_credits: recurring_transaction_rule.granted_credits.to_s,
                  source: :interval,
                  invoice_requires_successful_payment: false,
                  metadata: {}
                }
              )
          end
        end
      end

      context 'when wallet is created on a 31st' do
        let(:created_at) { DateTime.parse('31 Mar 2021') }
        let(:current_date) { DateTime.parse('30 Jun 2022') }

        it 'enqueues a job if the month count less than 31 days' do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect(WalletTransactions::CreateJob).to have_been_enqueued
              .with(
                organization_id: customer.organization_id,
                params: {
                  wallet_id: wallet.id,
                  paid_credits: recurring_transaction_rule.paid_credits.to_s,
                  granted_credits: recurring_transaction_rule.granted_credits.to_s,
                  source: :interval,
                  invoice_requires_successful_payment: false,
                  metadata: {}
                }
              )
          end
        end
      end
    end

    context 'when recurring transactions should be created yearly' do
      let(:interval) { :yearly }
      let(:current_date) { created_at.next_year }

      it 'enqueues a job on correct day' do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect(WalletTransactions::CreateJob).to have_been_enqueued
            .with(
              organization_id: customer.organization_id,
              params: {
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
                invoice_requires_successful_payment: false,
                metadata: {}
              }
            )
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context 'when wallet is created on 29th of february' do
        let(:created_at) { DateTime.parse('29 Feb 2020') }
        let(:current_date) { DateTime.parse('28 Feb 2022') }

        it 'enqueues a job on 28th of february when year is not a leap year' do
          travel_to(current_date) do
            create_interval_transactions_service.call

            expect(WalletTransactions::CreateJob).to have_been_enqueued
              .with(
                organization_id: customer.organization_id,
                params: {
                  wallet_id: wallet.id,
                  paid_credits: recurring_transaction_rule.paid_credits.to_s,
                  granted_credits: recurring_transaction_rule.granted_credits.to_s,
                  source: :interval,
                  invoice_requires_successful_payment: false,
                  metadata: {}
                }
              )
          end
        end
      end
    end

    context 'when on wallet creation day' do
      let(:interval) { :monthly }
      let(:customer) { create(:customer, timezone:) }
      let(:timezone) { nil }

      it 'does not enqueue a job' do
        travel_to(created_at) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context 'with customer timezone' do
        let(:timezone) { 'Pacific/Noumea' }

        it 'does not enqueue a job' do
          travel_to(created_at + 10.hours) do
            expect { create_interval_transactions_service.call }.not_to have_enqueued_job
          end
        end
      end
    end

    context 'when wallet transactions had already been created that day' do
      let(:interval) { :monthly }
      let(:current_date) { DateTime.parse('20 Mar 2021T12:00:00') }

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

      it 'does not enqueue a job' do
        travel_to(current_date) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
        end
      end

      context 'with customer timezone' do
        let(:customer) { create(:customer, timezone:) }
        let(:timezone) { 'Pacific/Noumea' }

        it 'does not enqueue a job' do
          travel_to(current_date + 10.hours) do
            expect { create_interval_transactions_service.call }.not_to have_enqueued_job
          end
        end
      end
    end

    context 'when rule requires successful payment' do
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
        DateTime.parse('20 Jun 2022').prev_occurring(created_at.strftime('%A').downcase.to_sym)
      end

      it 'follows the rule configuration' do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect(WalletTransactions::CreateJob).to have_been_enqueued
            .with(
              organization_id: customer.organization_id,
              params: {
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
                invoice_requires_successful_payment: true,
                metadata: {}
              }
            )
        end
      end
    end

    context 'when rule have medata' do
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

      let(:transaction_metadata) { [{'key' => 'valid_value', 'value' => 'also_valid'}] }

      let(:current_date) do
        DateTime.parse('20 Jun 2022').prev_occurring(created_at.strftime('%A').downcase.to_sym)
      end

      it 'enqueues a job with correct configuration' do
        travel_to(current_date) do
          create_interval_transactions_service.call

          expect(WalletTransactions::CreateJob).to have_been_enqueued
            .with(
              organization_id: customer.organization_id,
              params: {
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
                invoice_requires_successful_payment: false,
                metadata: transaction_metadata
              }
            )
        end
      end
    end
  end
end
