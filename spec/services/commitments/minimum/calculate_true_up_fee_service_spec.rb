# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commitments::Minimum::CalculateTrueUpFeeService, type: :service do
  subject(:service) { described_class.new(invoice_subscription:) }

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      subscription:,
      from_datetime:,
      to_datetime:,
      charges_from_datetime:,
      charges_to_datetime:,
      timestamp:,
    )
  end

  let(:from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
  let(:to_datetime) { DateTime.parse('2024-12-31T23:59:59') }
  let(:charges_from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
  let(:charges_to_datetime) { DateTime.parse('2024-12-31T23:59:59') }
  let(:timestamp) { DateTime.parse('2025-01-01T10:00:00') }
  let(:subscription) { create(:subscription, customer:, plan:, billing_time:, subscription_at:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription_at) { DateTime.parse('2024-01-01T00:00:00') }
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:billing_time) { :calendar }
  let(:bill_charges_monthly) { false }

  describe '#call' do
    subject(:service_call) { service.call }

    context 'when plan has no minimum commitment' do
      it 'returns result with zero amount cents' do
        expect(service_call.amount_cents).to eq(0)
      end
    end

    context 'when plan has minimum commitment' do
      let(:commitment) { create(:commitment, plan:, amount_cents: commitment_amount_cents) }
      let(:commitment_amount_cents) { 200 }
      let(:calculated_commitment_amount_cents) { service.__send__(:commitment_amount_cents) }

      let(:true_up_fee_amount_cents) do
        calculated_commitment_amount_cents - invoice_subscription.total_amount_cents
      end

      before { commitment }

      context 'when there are no fees' do
        it 'returns result with amount cents' do
          expect(service_call.amount_cents).to eq(calculated_commitment_amount_cents)
        end
      end

      context 'when there are subscription fees' do
        let(:plan) { create(:plan, organization:, interval:, bill_charges_monthly:) }
        let(:charge) { create(:standard_charge) }

        before do
          create(
            :fee,
            subscription: invoice_subscription.subscription,
            invoice: invoice_subscription.invoice,
          )

          create(
            :charge_fee,
            subscription: invoice_subscription.subscription,
            invoice: invoice_subscription.invoice,
            charge:,
            amount_cents: 300,
          )
        end

        context 'when subscription is anniversary' do
          let(:billing_time) { :anniversary }

          context 'when plan has yearly interval' do
            let(:interval) { :yearly }
            let(:from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
            let(:to_datetime) { DateTime.parse('2024-12-31T23:59:59') }
            let(:charges_from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
            let(:charges_to_datetime) { DateTime.parse('2024-12-31T23:59:59') }
            let(:timestamp) { DateTime.parse('2025-01-01T10:00:00') }

            context 'when plan is billed yearly' do
              context 'when fees total amount is greater or equal than the commitment amount' do
                it 'returns result with zero amount cents' do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context 'when fees total amount is smaller than the commitment amount' do
                let(:commitment_amount_cents) { 10_000 }

                it 'returns result with amount cents' do
                  expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
                end
              end
            end

            context 'when plan is billed monthly' do
              let(:bill_charges_monthly) { true }
              let(:commitment_amount_cents) { 10_000 }

              let(:invoice_subscription_previous) do
                create(
                  :invoice_subscription,
                  subscription:,
                  from_datetime: DateTime.parse('2024-01-01T00:00:00'),
                  to_datetime: DateTime.parse('2024-01-31T23:59:59'),
                  charges_from_datetime: DateTime.parse('2024-01-01T00:00:00'),
                  charges_to_datetime: DateTime.parse('2024-01-31T23:59:59'),
                  timestamp: DateTime.parse('2024-02-01T10:00:00'),
                )
              end

              before do
                create(
                  :fee,
                  subscription: invoice_subscription_previous.subscription,
                  invoice: invoice_subscription_previous.invoice,
                )

                create(
                  :charge_fee,
                  subscription: invoice_subscription_previous.subscription,
                  invoice: invoice_subscription_previous.invoice,
                  charge:,
                  amount_cents: 300,
                )
              end

              it 'returns result with amount cents' do
                expect(service_call.amount_cents).to eq(9_000)
              end
            end
          end

          context 'when plan has quarterly interval' do
            let(:interval) { :quarterly }
            let(:from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
            let(:to_datetime) { DateTime.parse('2024-03-31T23:59:59') }
            let(:charges_from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
            let(:charges_to_datetime) { DateTime.parse('2024-03-31T23:59:59') }
            let(:timestamp) { DateTime.parse('2024-04-01T10:00:00') }

            context 'when fees total amount is greater or equal than the commitment amount' do
              it 'returns result with zero amount cents' do
                expect(service_call.amount_cents).to eq(0)
              end
            end

            context 'when fees total amount is smaller than the commitment amount' do
              let(:commitment_amount_cents) { 10_000 }

              it 'returns result with amount cents' do
                expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
              end
            end
          end

          context 'when plan has monthly interval' do
            let(:interval) { :monthly }
            let(:from_datetime) { DateTime.parse('2024-02-01T00:00:00') }
            let(:to_datetime) { DateTime.parse('2024-02-29T23:59:59') }
            let(:charges_from_datetime) { DateTime.parse('2024-02-01T00:00:00') }
            let(:charges_to_datetime) { DateTime.parse('2024-02-29T23:59:59') }
            let(:timestamp) { DateTime.parse('2024-03-01T10:00:00') }

            context 'when fees total amount is greater or equal than the commitment amount' do
              it 'returns result with zero amount cents' do
                expect(service_call.amount_cents).to eq(0)
              end
            end

            context 'when fees total amount is smaller than the commitment amount' do
              let(:commitment_amount_cents) { 10_000 }

              it 'returns result with amount cents' do
                expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
              end
            end
          end

          context 'when plan has weekly interval' do
            let(:interval) { :weekly }
            let(:from_datetime) { DateTime.parse('2024-02-05T00:00:00') }
            let(:to_datetime) { DateTime.parse('2024-02-11T23:59:59') }
            let(:charges_from_datetime) { DateTime.parse('2024-02-05T00:00:00') }
            let(:charges_to_datetime) { DateTime.parse('2024-02-11T23:59:59') }
            let(:timestamp) { DateTime.parse('2024-02-12T10:00:00') }

            context 'when fees total amount is greater or equal than the commitment amount' do
              it 'returns result with zero amount cents' do
                expect(service_call.amount_cents).to eq(0)
              end
            end

            context 'when fees total amount is smaller than the commitment amount' do
              let(:commitment_amount_cents) { 10_000 }

              it 'returns result with amount cents' do
                expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
              end
            end
          end
        end

        context 'when subscription is calendar' do
          let(:billing_time) { :calendar }

          context 'when plan has yearly interval' do
            let(:interval) { :yearly }
            let(:from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
            let(:to_datetime) { DateTime.parse('2024-12-31T23:59:59') }
            let(:charges_from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
            let(:charges_to_datetime) { DateTime.parse('2024-12-31T23:59:59') }
            let(:timestamp) { DateTime.parse('2025-01-01T10:00:00') }

            context 'when plan is billed yearly' do
              context 'when fees total amount is greater or equal than the commitment amount' do
                it 'returns result with zero amount cents' do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context 'when fees total amount is smaller than the commitment amount' do
                let(:commitment_amount_cents) { 10_000 }

                it 'returns result with amount cents' do
                  expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
                end
              end
            end

            context 'when plan is billed monthly' do
              let(:bill_charges_monthly) { true }
              let(:commitment_amount_cents) { 10_000 }

              let(:invoice_subscription_previous) do
                create(
                  :invoice_subscription,
                  subscription:,
                  from_datetime:,
                  to_datetime: DateTime.parse('2024-01-31T23:59:59'),
                  charges_from_datetime: DateTime.parse('2024-01-01T00:00:00'),
                  charges_to_datetime: DateTime.parse('2024-01-31T23:59:59'),
                  timestamp: DateTime.parse('2024-02-01T10:00:00'),
                )
              end

              before do
                create(
                  :fee,
                  subscription: invoice_subscription_previous.subscription,
                  invoice: invoice_subscription_previous.invoice,
                )

                create(
                  :charge_fee,
                  subscription: invoice_subscription_previous.subscription,
                  invoice: invoice_subscription_previous.invoice,
                  charge:,
                  amount_cents: 300,
                )
              end

              context 'when subscription starts at the beginning of the period' do
                let(:from_datetime) { DateTime.parse('2024-01-01T00:00:00') }

                it 'returns result with amount cents' do
                  expect(service_call.amount_cents).to eq(9_000)
                end
              end

              context 'when subscription does not start at the beginning of the period' do
                let(:from_datetime) { DateTime.parse('2024-01-02T00:00:00') }

                it 'returns result with amount cents prorated' do
                  expect(service_call.amount_cents).to eq(8_973)
                end
              end
            end
          end

          context 'when plan has quarterly interval' do
            let(:interval) { :quarterly }
            let(:from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
            let(:to_datetime) { DateTime.parse('2024-03-31T23:59:59') }
            let(:charges_from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
            let(:charges_to_datetime) { DateTime.parse('2024-03-31T23:59:59') }
            let(:timestamp) { DateTime.parse('2024-04-01T10:00:00') }

            context 'when fees total amount is greater or equal than the commitment amount' do
              it 'returns result with zero amount cents' do
                expect(service_call.amount_cents).to eq(0)
              end
            end

            context 'when fees total amount is smaller than the commitment amount' do
              let(:commitment_amount_cents) { 10_000 }

              it 'returns result with amount cents' do
                expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
              end
            end
          end

          context 'when plan has monthly interval' do
            let(:interval) { :monthly }
            let(:from_datetime) { DateTime.parse('2024-02-01T00:00:00') }
            let(:to_datetime) { DateTime.parse('2024-02-29T23:59:59') }
            let(:charges_from_datetime) { DateTime.parse('2024-02-01T00:00:00') }
            let(:charges_to_datetime) { DateTime.parse('2024-02-29T23:59:59') }
            let(:timestamp) { DateTime.parse('2024-03-01T10:00:00') }

            context 'when fees total amount is greater or equal than the commitment amount' do
              it 'returns result with zero amount cents' do
                expect(service_call.amount_cents).to eq(0)
              end
            end

            context 'when fees total amount is smaller than the commitment amount' do
              let(:commitment_amount_cents) { 10_000 }

              it 'returns result with amount cents' do
                expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
              end
            end
          end

          context 'when plan has weekly interval' do
            let(:interval) { :weekly }
            let(:from_datetime) { DateTime.parse('2024-02-05T00:00:00') }
            let(:to_datetime) { DateTime.parse('2024-02-11T23:59:59') }
            let(:charges_from_datetime) { DateTime.parse('2024-02-05T00:00:00') }
            let(:charges_to_datetime) { DateTime.parse('2024-02-11T23:59:59') }
            let(:timestamp) { DateTime.parse('2024-02-12T10:00:00') }

            context 'when fees total amount is greater or equal than the commitment amount' do
              it 'returns result with zero amount cents' do
                expect(service_call.amount_cents).to eq(0)
              end
            end

            context 'when fees total amount is smaller than the commitment amount' do
              let(:commitment_amount_cents) { 10_000 }

              it 'returns result with amount cents' do
                expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
              end
            end
          end
        end
      end
    end
  end
end
