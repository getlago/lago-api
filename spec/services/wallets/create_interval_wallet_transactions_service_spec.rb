# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::CreateIntervalWalletTransactionsService, type: :service do
  subject(:create_interval_transactions_service) { described_class.new }

  describe '.call' do
    let(:wallet) { create(:wallet, customer:, created_at:) }
    let(:created_at) { DateTime.parse('20 Feb 2021') }
    let(:customer) { create(:customer) }

    let(:recurring_transaction_rule) do
      create(
        :recurring_transaction_rule,
        rule_type: :interval,
        wallet:,
        interval:,
        created_at: created_at + 1.second,
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
              wallet_id: wallet.id,
              paid_credits: recurring_transaction_rule.paid_credits.to_s,
              granted_credits: recurring_transaction_rule.granted_credits.to_s,
              source: :interval,
            )
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { create_interval_transactions_service.call }.not_to have_enqueued_job
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
              wallet_id: wallet.id,
              paid_credits: recurring_transaction_rule.paid_credits.to_s,
              granted_credits: recurring_transaction_rule.granted_credits.to_s,
              source: :interval,
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
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
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
              wallet_id: wallet.id,
              paid_credits: recurring_transaction_rule.paid_credits.to_s,
              granted_credits: recurring_transaction_rule.granted_credits.to_s,
              source: :interval,
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
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
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
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
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
              wallet_id: wallet.id,
              paid_credits: recurring_transaction_rule.paid_credits.to_s,
              granted_credits: recurring_transaction_rule.granted_credits.to_s,
              source: :interval,
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
                wallet_id: wallet.id,
                paid_credits: recurring_transaction_rule.paid_credits.to_s,
                granted_credits: recurring_transaction_rule.granted_credits.to_s,
                source: :interval,
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
          created_at: current_date - 1.hour,
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
  end
end
