# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commitments::CalculateAmountService, type: :service do
  subject(:apply_service) { described_class.new(commitment:, invoice_subscription:) }

  let(:invoice_subscription) do
    create(:invoice_subscription, subscription:, from_datetime:, to_datetime:)
  end

  let(:subscription) { create(:active_subscription, customer:, plan:, billing_time:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:, interval:) }
  let(:billing_time) { :calendar }

  describe 'call' do
    context 'when plan has weekly interval' do
      let(:amount_cents) { 3_000 }
      let(:interval) { :weekly }
      let(:from_datetime) { DateTime.parse('2024-01-02T00:00:00') }
      let(:to_datetime) { DateTime.parse('2024-01-07T23:59:59') }

      context 'when subscription is calendar' do
        let(:billing_time) { :calendar }

        context 'when there is no commitment' do
          let(:commitment) { nil }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(0)
          end
        end

        context 'when a commitment exists for a plan' do
          let(:commitment) { create(:commitment, plan:, amount_cents:) }

          before { commitment }

          it { is_expected.to delegate_method(:subscription).to(:invoice_subscription) }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(2_571)
          end
        end
      end

      context 'when subscription is anniversary' do
        let(:billing_time) { :anniversary }

        context 'when there is no commitment' do
          let(:commitment) { nil }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(0)
          end
        end

        context 'when a commitment exists for a plan' do
          let(:commitment) { create(:commitment, plan:, amount_cents:) }

          it { is_expected.to delegate_method(:subscription).to(:invoice_subscription) }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(commitment.amount_cents)
          end
        end
      end
    end

    context 'when plan has monthly interval' do
      let(:amount_cents) { 20_000 }
      let(:interval) { :monthly }
      let(:from_datetime) { DateTime.parse('2024-01-15T00:00:00') }
      let(:to_datetime) { DateTime.parse('2024-01-31T23:59:59') }

      context 'when subscription is calendar' do
        let(:billing_time) { :calendar }

        context 'when there is no commitment' do
          let(:commitment) { nil }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(0)
          end
        end

        context 'when a commitment exists for a plan' do
          let(:commitment) { create(:commitment, plan:, amount_cents:) }

          it { is_expected.to delegate_method(:subscription).to(:invoice_subscription) }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(10_968)
          end
        end
      end

      context 'when subscription is anniversary' do
        let(:billing_time) { :anniversary }

        context 'when there is no commitment' do
          let(:commitment) { nil }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(0)
          end
        end

        context 'when a commitment exists for a plan' do
          let(:commitment) { create(:commitment, plan:, amount_cents:) }

          it { is_expected.to delegate_method(:subscription).to(:invoice_subscription) }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(commitment.amount_cents)
          end
        end
      end
    end

    context 'when plan has quarterly interval' do
      let(:amount_cents) { 40_000 }
      let(:interval) { :quarterly }
      let(:from_datetime) { DateTime.parse('2024-01-15T00:00:00') }
      let(:to_datetime) { DateTime.parse('2024-03-31T23:59:59') }

      context 'when subscription is calendar' do
        let(:billing_time) { :calendar }

        context 'when there is no commitment' do
          let(:commitment) { nil }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(0)
          end
        end

        context 'when a commitment exists for a plan' do
          let(:commitment) { create(:commitment, plan:, amount_cents:) }

          before { commitment }

          it { is_expected.to delegate_method(:subscription).to(:invoice_subscription) }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(33_846)
          end
        end
      end

      context 'when subscription is anniversary' do
        let(:billing_time) { :anniversary }

        context 'when there is no commitment' do
          let(:commitment) { nil }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(0)
          end
        end

        context 'when a commitment exists for a plan' do
          let(:commitment) { create(:commitment, plan:, amount_cents:) }

          it { is_expected.to delegate_method(:subscription).to(:invoice_subscription) }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(commitment.amount_cents)
          end
        end
      end
    end

    context 'when plan has yearly interval' do
      let(:amount_cents) { 200_000 }
      let(:interval) { :yearly }
      let(:from_datetime) { DateTime.parse('2024-01-15T00:00:00') }
      let(:to_datetime) { DateTime.parse('2024-12-31T23:59:59') }

      context 'when subscription is calendar' do
        let(:billing_time) { :calendar }

        context 'when there is no commitment' do
          let(:commitment) { nil }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(0)
          end
        end

        context 'when a commitment exists for a plan' do
          let(:commitment) { create(:commitment, plan:, amount_cents:) }

          before { commitment }

          it { is_expected.to delegate_method(:subscription).to(:invoice_subscription) }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(192350)
          end
        end
      end

      context 'when subscription is anniversary' do
        let(:billing_time) { :anniversary }

        context 'when there is no commitment' do
          let(:commitment) { nil }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(0)
          end
        end

        context 'when a commitment exists for a plan' do
          let(:commitment) { create(:commitment, plan:, amount_cents:) }

          it { is_expected.to delegate_method(:subscription).to(:invoice_subscription) }

          it 'returns result' do
            result = apply_service.call

            expect(result.commitment_amount_cents).to eq(commitment.amount_cents)
          end
        end
      end
    end
  end
end
