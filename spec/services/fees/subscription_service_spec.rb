# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::SubscriptionService do
  subject(:fees_subscription_service) { described_class.new(invoice) }

  let(:plan) do
    create(
      :plan,
      amount_cents: 100,
      amount_currency: 'EUR',
    )
  end

  context 'when invoice is on a full period' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: Time.zone.parse('2022-01-01 00:01'),
      )
    end

    let(:invoice) do
      from_date = Time.zone.parse('2022-03-01 00:00')

      create(
        :invoice,
        subscription: subscription,
        from_date: from_date,
        to_date: from_date.end_of_month,
      )
    end

    it 'creates a fee' do
      result = fees_subscription_service.create
      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.id).not_to be_nil
        expect(created_fee.invoice_id).to eq(invoice.id)
        expect(created_fee.amount_cents).to eq(plan.amount_cents)
        expect(created_fee.amount_currency).to eq(plan.amount_currency)
        expect(created_fee.vat_amount_cents).to eq(20)
        expect(created_fee.vat_rate).to eq(20.0)
      end
    end

    context 'when plan has a trial period' do
      before do
        plan.update(trial_period: trial_duration)
        subscription.update(started_at: invoice.from_date)
      end

      context 'when trial end in period' do
        let(:trial_duration) { 3 }

        it 'creates a fee with prorated amount based on trial' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.amount_cents).to eq(90)
          end
        end
      end

      context 'when trial end after end of period' do
        let(:trial_duration) { 45 }

        it 'creates a fee with zero amount' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(0)
        end
      end
    end
  end

  context 'when subscription has never been billed' do
    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.end_of_month.to_date,
      )
    end

    context 'when plan is monthly' do
      before { plan.monthly! }

      context 'when subscription start is on the 1st of the month' do
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: Time.zone.parse('2022-01-01 00:01'),
          )
        end

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(plan.amount_cents)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(20)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end

        context 'when plan has a trial period' do
          before { plan.update(trial_period: trial_duration) }

          context 'when trial end during period' do
            let(:trial_duration) { 3 }

            it 'creates a fee with prorated amount based on trial' do
              result = fees_subscription_service.create
              created_fee = result.fee

              expect(created_fee.amount_cents).to eq(90)
            end
          end

          context 'when trial end after end of period' do
            let(:trial_duration) { 45 }

            it 'creates a fee with zero amount' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(0)
            end
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            expect(created_fee.amount_cents).to eq(100)
          end

          context 'when plan has a trial period' do
            before { plan.update(trial_period: trial_duration) }

            context 'when trial end in period' do
              let(:trial_duration) { 3 }

              it 'creates a fee with prorated amount based on trial' do
                result = fees_subscription_service.create
                created_fee = result.fee

                expect(created_fee.amount_cents).to eq(90)
              end
            end

            context 'when trial end after period' do
              let(:trial_duration) { 45 }

              it 'creates a fee with zero amount' do
                result = fees_subscription_service.create
                created_fee = result.fee

                expect(created_fee.amount_cents).to eq(0)
              end
            end
          end
        end
      end

      context 'when subscription start is on any other day' do
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: Time.zone.parse('2022-03-15 00:00:00'),
          )
        end

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(55)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(11)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end

        context 'when plan has a trial period' do
          before { plan.update(trial_period: trial_duration) }

          context 'when trial end during the period' do
            let(:trial_duration) { 3 }

            it 'creates a fee with prorated amount based on trial' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(45)
            end
          end

          context 'when trial end after the period end' do
            let(:trial_duration) { 45 }

            it 'creates a fee with zero amount' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(0)
            end
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(55)
            end
          end

          context 'when plan has a trial period' do
            before { plan.update(trial_period: trial_duration) }

            context 'when trial end during the period' do
              let(:trial_duration) { 3 }

              it 'creates a fee with prorated amount based on trial' do
                result = fees_subscription_service.create

                expect(result.fee.amount_cents).to eq(45)
              end
            end

            context 'when trial end after the period end' do
              let(:trial_duration) { 45 }

              it 'creates a fee with zero amount' do
                result = fees_subscription_service.create

                expect(result.fee.amount_cents).to eq(0)
              end
            end
          end
        end
      end
    end

    context 'when plan is yearly' do
      before { plan.yearly! }

      context 'when subscription start is on the 1st day of the year' do
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: Time.zone.now.beginning_of_year,
          )
        end

        before do
          invoice.update!(
            from_date: subscription.started_at.beginning_of_year,
            to_date: subscription.started_at.end_of_year,
          )
        end

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(plan.amount_cents)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(20)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(plan.amount_cents)
            end
          end
        end
      end

      context 'when subscription start is on any other day' do
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: Time.zone.parse('2022-03-15 00:00:00'),
          )
        end

        before { invoice.update!(to_date: subscription.started_at.end_of_year) }

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(80)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(16)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(80)
            end
          end
        end
      end
    end
  end

  context 'when subscription has already been billed once on an other period' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: Time.zone.parse('2022-01-01 00:00'),
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.end_of_month.to_date,
      )
    end

    before do
      other_invoice = create(:invoice, subscription: subscription)
      create(:fee, subscription: subscription, invoice: other_invoice)
    end

    it 'creates a fee with full period amount' do
      result = fees_subscription_service.create
      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.amount_cents).to eq(100)
      end
    end

    context 'when plan has trial period' do
      before { plan.update(trial_period: trial_duration) }

      context 'when trial end during period' do
        let(:trial_duration) { 3 }

        it 'creates a fee with prorated amount on trial period' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(90)
        end
      end

      context 'when trial end after period' do
        let(:trial_duration) { 45 }

        it 'creates a fee with 0 amount' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(0)
        end
      end
    end
  end

  context 'when plan interval is not implemented' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: Time.zone.parse('2022-01-19 00:00').beginning_of_week,
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.end_of_month.to_date,
      )
    end

    before do
      plan.weekly!
    end

    it 'throws an NotImpementedError' do
      expect { fees_subscription_service.create }.to raise_error(NotImplementedError)
    end
  end

  context 'when already billed fee' do
    let(:plan) do
      create(
        :plan,
        amount_cents: 100,
        amount_currency: 'EUR',
      )
    end

    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: Time.zone.parse('2022-01-01 00:00'),
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at + 1.month,
        to_date: subscription.started_at + 2.months,
      )
    end

    before do
      create(:fee, subscription: subscription, invoice: invoice)
    end

    it 'creates a fee' do
      expect { fees_subscription_service.create }.not_to change(Fee, :count)
    end
  end

  context 'when billing a newly terminated subscription' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        status: :terminated,
        started_at: Time.zone.parse('2022-03-15 00:00:00'),
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at.beginning_of_month.to_date,
        to_date: subscription.started_at.to_date + 5.days,
      )
    end

    before do
      plan.update!(pay_in_advance: false)
    end

    it 'creates a fee' do
      result = fees_subscription_service.create
      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.id).not_to be_nil
        expect(created_fee.invoice_id).to eq(invoice.id)
        expect(created_fee.amount_cents).to eq(65)
        expect(created_fee.amount_currency).to eq(plan.amount_currency)
        expect(created_fee.vat_amount_cents).to eq(13)
        expect(created_fee.vat_rate).to eq(20.0)
      end
    end

    context 'with a next subscription' do
      before do
        create(:subscription, previous_subscription: subscription)
      end

      it 'creates a fee' do
        result = fees_subscription_service.create
        created_fee = result.fee

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.amount_cents).to eq(64)
          expect(created_fee.amount_currency).to eq(plan.amount_currency)
          expect(created_fee.vat_amount_cents).to eq(12)
          expect(created_fee.vat_rate).to eq(20.0)
        end
      end
    end

    context 'when plan has trial period' do
      before do
        plan.update(trial_period: trial_duration)
        create(:subscription, previous_subscription: subscription)
      end

      context 'when trial end before termination date' do
        let(:trial_duration) { 3 }

        it 'creates a fee with prorated amount based on trial period' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(10)
        end
      end

      context 'when trial end after termination date' do
        let(:trial_duration) { 45 }

        it 'creates a fee with zero amount' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(0)
        end
      end
    end
  end

  context 'when billing an new upgraded subscription' do
    let(:previous_plan) { create(:plan, pay_in_advance: true, amount_cents: 80) }
    let(:previous_subscription) { create(:subscription, status: :terminated, plan: previous_plan) }

    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: Time.zone.parse('2022-03-15 00:00:00'),
        previous_subscription: previous_subscription,
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at,
        to_date: subscription.started_at.to_date.end_of_month,
      )
    end

    context 'when previous subscription was payed in advance' do
      it 'creates a subscription' do
        result = fees_subscription_service.create
        created_fee = result.fee

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.amount_cents).to eq(11)
          expect(created_fee.amount_currency).to eq(plan.amount_currency)
          expect(created_fee.vat_amount_cents).to eq(2)
          expect(created_fee.vat_rate).to eq(20.0)
        end
      end

      context 'when plan has trial period' do
        before { plan.update(trial_period: trial_duration) }

        context 'when trial period end before end of period' do
          let(:trial_duration) { 3 }

          it 'creates a fee with prorated amount based on the trial period' do
            result = fees_subscription_service.create

            expect(result.fee.amount_cents).to eq(9)
          end
        end

        context 'when trial period end after end of period' do
          let(:trial_duration) { 45 }

          it 'creates a fee with zero amount' do
            result = fees_subscription_service.create

            expect(result.fee.amount_cents).to eq(0)
          end
        end
      end
    end

    context 'when previous subscription was payed in arrear' do
      before { previous_plan.update!(pay_in_advance: false) }

      it 'creates a subscription' do
        result = fees_subscription_service.create
        created_fee = result.fee

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.amount_cents).to eq(55)
          expect(created_fee.amount_currency).to eq(plan.amount_currency)
          expect(created_fee.vat_amount_cents).to eq(11)
          expect(created_fee.vat_rate).to eq(20.0)
        end
      end

      context 'when plan has trial period' do
        before { plan.update(trial_period: trial_duration) }

        context 'when trial period end before period end' do
          let(:trial_duration) { 3 }

          it 'creates a fee with prorated amount based on the trial' do
            result = fees_subscription_service.create

            expect(result.fee.amount_cents).to eq(45)
          end
        end

        context 'when trial period end after period end' do
          let(:trial_duration) { 45 }

          it 'creates a fee with zero amount' do
            result = fees_subscription_service.create

            expect(result.fee.amount_cents).to eq(0)
          end
        end
      end
    end
  end
end
