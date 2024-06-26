# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CalculateFeesService, type: :service do
  subject(:invoice_service) do
    described_class.new(
      invoice:,
      recurring:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:recurring) { false }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      currency: 'EUR',
      issuing_date: Time.zone.at(timestamp).to_date,
      customer: subscription.customer
    )
  end

  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      billing_time:,
      subscription_at: started_at,
      started_at:,
      created_at:,
      status:,
      terminated_at:
    )
  end

  let(:date_service) do
    Subscriptions::DatesService.new_instance(
      subscription,
      Time.zone.at(timestamp),
      current_usage: subscription.terminated? && subscription.upgraded?
    )
  end

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      subscription:,
      invoice:,
      timestamp:,
      from_datetime: date_service.from_datetime,
      to_datetime: date_service.to_datetime,
      charges_from_datetime: date_service.charges_from_datetime,
      charges_to_datetime: date_service.charges_to_datetime
    )
  end

  let(:invoice_subscriptions) { [invoice_subscription] }

  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:timestamp) { Time.zone.now.beginning_of_month }
  let(:started_at) { Time.zone.now - 2.years }
  let(:created_at) { started_at }
  let(:terminated_at) { nil }
  let(:status) { :active }

  let(:plan) { create(:plan, organization:, interval:, pay_in_advance:, trial_period:) }
  let(:pay_in_advance) { false }
  let(:billing_time) { :calendar }
  let(:interval) { 'monthly' }
  let(:trial_period) { 0 }

  let(:charge) { create(:standard_charge, plan: subscription.plan, charge_model: 'standard') }

  before do
    tax
    charge
    invoice_subscriptions

    allow(SegmentTrackJob).to receive(:perform_later)
    allow(Invoices::Payments::StripeCreateJob).to receive(:perform_later).and_call_original
    allow(Invoices::Payments::GocardlessCreateJob).to receive(:perform_later).and_call_original
  end

  describe '#call' do
    context 'when subscription is billed on anniversary date' do
      let(:timestamp) { DateTime.parse('07 Mar 2022') }
      let(:started_at) { DateTime.parse('06 Jun 2021').to_date }
      let(:subscription_at) { started_at }
      let(:billing_time) { :anniversary }

      it 'creates subscription and charge fees' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(invoice.subscriptions.first).to eq(subscription)
          expect(invoice.payment_status).to eq('pending')
          expect(invoice.fees.subscription_kind.count).to eq(1)
          expect(invoice.fees.charge_kind.count).to eq(1)

          invoice_subscription = invoice.invoice_subscriptions.first
          expect(invoice_subscription).to have_attributes(
            to_datetime: match_datetime(DateTime.parse('2022-03-05 23:59:59')),
            from_datetime: match_datetime(DateTime.parse('2022-02-06 00:00:00'))
          )
        end
      end

      context 'when charge is pay_in_advance, not recurring and invoiceable' do
        let(:charge) do
          create(
            :standard_charge,
            :pay_in_advance,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: true
          )
        end

        it 'does not create a charge fee' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.fees.charge_kind.count).to eq(0)
          end
        end
      end

      context 'when charge is pay_in_advance, recurring and invoiceable' do
        let(:billable_metric) do
          create(:billable_metric, aggregation_type: 'unique_count_agg', recurring: true, field_name: 'item_id')
        end
        let(:charge) do
          create(
            :standard_charge,
            :pay_in_advance,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: true,
            billable_metric:
          )
        end

        it 'creates a charge fee' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.fees.charge_kind.count).to eq(1)
          end
        end
      end

      context 'when charge is pay_in_advance, not recurring and not invoiceable' do
        let(:charge) do
          create(
            :standard_charge,
            :pay_in_advance,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: false
          )
        end

        it 'does not create a charge fee' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(Fee.charge_kind.count).to eq(0)
          end
        end
      end

      context 'when charge is pay_in_advance, recurring and not invoiceable' do
        let(:billable_metric) do
          create(:billable_metric, aggregation_type: 'unique_count_agg', recurring: true, field_name: 'item_id')
        end
        let(:charge) do
          create(
            :standard_charge,
            :pay_in_advance,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: false,
            billable_metric:
          )
        end

        it 'creates a charge fee' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(Fee.charge_kind.where(invoice_id: nil).count).to eq(1)
          end
        end
      end

      context 'when charge is pay_in_arrears and not invoiceable' do
        let(:charge) do
          create(
            :standard_charge,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: false
          )
        end

        it 'does not create a charge fee' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(Fee.charge_kind.count).to eq(0)
          end
        end
      end
    end

    context 'when billed for the first time' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { timestamp - 3.days }

      context 'when plan has no other requirements' do
        it 'creates subscription and charge fees' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.subscriptions.first).to eq(subscription)
            expect(invoice.fees.subscription_kind.count).to eq(1)
            expect(invoice.fees.charge_kind.count).to eq(1)
            expect(invoice.fees.commitment_kind.count).to eq(0)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime((timestamp - 1.day).end_of_day),
              from_datetime: match_datetime(subscription.subscription_at.beginning_of_day)
            )
          end
        end
      end

      context 'when plan has minimum commitment' do
        before do
          create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
        end

        it 'creates subscription, charge and commitment fees' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.subscriptions.first).to eq(subscription)
            expect(invoice.fees.subscription_kind.count).to eq(1)
            expect(invoice.fees.charge_kind.count).to eq(1)
            expect(invoice.fees.commitment_kind.count).to eq(1)
          end
        end
      end

      context 'when plan has non invoiceable, recurring, pay in advance charge' do
        before do
          create(
            :standard_charge,
            :pay_in_advance,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: false,
            billable_metric: create(:billable_metric, aggregation_type: 'unique_count_agg', recurring: true, field_name: 'item_id')
          )
        end

        it 'creates subscription, charge and commitment fees' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.fees.charge_kind.count).to eq(1)
            expect(Fee.where(invoice_id: nil).count).to eq(1)
          end
        end
      end
    end

    context 'when two subscriptions are given' do
      let(:subscription2) do
        create(
          :subscription,
          plan:,
          customer: subscription.customer,
          subscription_at: (Time.zone.now - 2.years).to_date,
          started_at: Time.zone.now - 2.years
        )
      end

      let(:invoice_subscription2) do
        create(
          :invoice_subscription,
          subscription: subscription2,
          invoice:,
          timestamp:,
          from_datetime: date_service.from_datetime,
          to_datetime: date_service.to_datetime,
          charges_from_datetime: date_service.charges_from_datetime,
          charges_to_datetime: date_service.charges_to_datetime
        )
      end

      let(:invoice_subscriptions) { [invoice_subscription, invoice_subscription2] }

      context 'when plan has no minimum commitment' do
        it 'creates subscription and charges fees for both' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(invoice.subscriptions.to_a).to match_array([subscription, subscription2])
            expect(invoice.payment_status).to eq('pending')
            expect(invoice.fees.subscription_kind.count).to eq(2)
            expect(invoice.fees.charge_kind.count).to eq(2)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime((timestamp - 1.day).end_of_day),
              from_datetime: match_datetime((timestamp - 1.month).beginning_of_day)
            )
          end
        end
      end

      context 'when plan has minimum commitment' do
        before do
          create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
        end

        it 'creates subscription, charges and commitment fees for both' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(invoice.subscriptions.to_a).to match_array([subscription, subscription2])
            expect(invoice.payment_status).to eq('pending')
            expect(invoice.fees.subscription_kind.count).to eq(2)
            expect(invoice.fees.charge_kind.count).to eq(2)
            expect(invoice.fees.commitment_kind.count).to eq(2)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime((timestamp - 1.day).end_of_day),
              from_datetime: match_datetime((timestamp - 1.month).beginning_of_day)
            )
          end
        end
      end
    end

    context 'when subscription is terminated' do
      let(:status) { :terminated }
      let(:timestamp) { Time.zone.now.beginning_of_month - 1.day }
      let(:started_at) { Time.zone.today - 3.months }
      let(:terminated_at) { timestamp - 2.days }

      context 'when plan has minimum commitment' do
        before do
          create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
        end

        it 'creates a subscription and a commitment fee' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(invoice.fees.subscription_kind.count).to eq(1)
            expect(invoice.fees.commitment_kind.count).to eq(1)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime(terminated_at),
              from_datetime: match_datetime(terminated_at.beginning_of_month)
            )
          end
        end
      end

      context 'when plan has no minimum commitment' do
        it 'creates a subscription fee' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(invoice.fees.subscription_kind.count).to eq(1)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime(terminated_at),
              from_datetime: match_datetime(terminated_at.beginning_of_month)
            )
          end
        end
      end

      context 'when charges are pay in advance and billable metric is recurring' do
        let(:billable_metric) do
          create(:billable_metric, aggregation_type: 'unique_count_agg', recurring: true, field_name: 'item_id')
        end

        let(:charge) do
          create(
            :standard_charge,
            :pay_in_advance,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: true,
            billable_metric:
          )
        end

        context 'when plan no minimum commitment' do
          it 'does not create a charge fee or a commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.charge_kind.count).to eq(0)
              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          it 'does not create a charge fee but it creates a commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.charge_kind.count).to eq(0)
              expect(invoice.fees.commitment_kind.count).to eq(1)
            end
          end
        end
      end

      context 'when charges are pay in arrear and billable metric is recurring' do
        let(:billable_metric) do
          create(:billable_metric, aggregation_type: 'unique_count_agg', recurring: true, field_name: 'item_id')
        end
        let(:charge) do
          create(
            :standard_charge,
            pay_in_advance: false,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: true,
            billable_metric:,
            prorated: false
          )
        end

        context 'when plan no minimum commitment' do
          it 'creates a charge fee but no minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.charge_kind.count).to eq(1)
              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          it 'creates a charge fee and a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.charge_kind.count).to eq(1)
              expect(invoice.fees.commitment_kind.count).to eq(1)
            end
          end
        end
      end

      context 'when termination is part of upgrade and charges are not billable' do
        let(:new_subscription) do
          create(
            :subscription,
            plan:,
            previous_subscription: subscription,
            subscription_at: started_at.to_date,
            started_at: terminated_at + 1.day,
            created_at: terminated_at + 1.day
          )
        end

        let(:billable_metric) do
          create(:billable_metric, aggregation_type: 'unique_count_agg', recurring: true, field_name: 'item_id')
        end

        let(:charge) do
          create(
            :standard_charge,
            :pay_in_advance,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: true,
            billable_metric:
          )
        end

        before { new_subscription }

        context 'when plan has no minimum commitment' do
          it 'does not create a charge fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.charge_kind.count).to eq(0)
            end
          end

          it 'does not create a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          it 'does not create a charge fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.charge_kind.count).to eq(0)
            end
          end

          it 'creates a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(1)
            end
          end
        end
      end

      context 'when termination is part of upgrade, charges are paid in arrears and BM is recurring' do
        let(:new_subscription) do
          create(
            :subscription,
            plan:,
            previous_subscription: subscription,
            subscription_at: started_at.to_date,
            started_at: terminated_at + 1.day,
            created_at: terminated_at + 1.day
          )
        end

        let(:billable_metric) do
          create(:billable_metric, aggregation_type: 'unique_count_agg', recurring: true, field_name: 'item_id')
        end

        let(:charge) do
          create(
            :standard_charge,
            pay_in_advance: false,
            plan: subscription.plan,
            charge_model: 'standard',
            invoiceable: true,
            billable_metric:,
            prorated: false
          )
        end

        before { new_subscription }

        context 'when plan has no minimum commitment' do
          it 'does not create a charge fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.charge_kind.count).to eq(0)
            end
          end

          it 'does not create a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          it 'does not create a charge fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.charge_kind.count).to eq(0)
            end
          end

          it 'creates a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(1)
            end
          end
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('22 Mar 2022') }
        let(:started_at) { DateTime.parse('2021-06-06 05:00:00') }
        let(:subscription_at) { started_at }
        let(:billing_time) { 'anniversary' }

        context 'when plan has no minimum commitment' do
          it 'creates subscription fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success
              expect(invoice.fees.subscription_kind.count).to eq(1)

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                to_datetime: match_datetime(terminated_at),
                from_datetime: match_datetime(DateTime.parse('2022-03-06 00:00:00'))
              )
            end
          end

          it 'does not create a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          it 'creates subscription fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success
              expect(invoice.fees.subscription_kind.count).to eq(1)

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                to_datetime: match_datetime(terminated_at),
                from_datetime: match_datetime(DateTime.parse('2022-03-06 00:00:00'))
              )
            end
          end

          it 'creates a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(1)
            end
          end
        end
      end
    end

    context 'when plan is pay in advance' do
      let(:pay_in_advance) { true }

      context 'when billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Mar 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2021').to_date }
        let(:subscription_at) { started_at }
        let(:billing_time) { :anniversary }

        context 'when plan has no minimum commitment' do
          it 'creates a subscription fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success
              expect(invoice.subscriptions.first).to eq(subscription)
              expect(invoice.payment_status).to eq('pending')
              expect(invoice.fees.subscription_kind.count).to eq(1)
              expect(invoice).to have_empty_charge_fees

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                to_datetime: match_datetime(DateTime.parse('2022-04-05 23:59:59')),
                from_datetime: match_datetime(DateTime.parse('2022-03-06 00:00:00'))
              )
            end
          end

          it 'does not create a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          it 'creates a subscription fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success
              expect(invoice.subscriptions.first).to eq(subscription)
              expect(invoice.payment_status).to eq('pending')
              expect(invoice.fees.subscription_kind.count).to eq(1)
              expect(invoice).to have_empty_charge_fees

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                to_datetime: match_datetime(DateTime.parse('2022-04-05 23:59:59')),
                from_datetime: match_datetime(DateTime.parse('2022-03-06 00:00:00'))
              )
            end
          end

          it 'does not create a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end
      end

      context 'when plan is in trial period' do
        let(:trial_period) { 45 }
        let(:started_at) { 40.days.ago }

        it 'does not create a subscription fee' do
          subscription.created_at
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.fees.subscription_kind.count).to eq(0)
          end
        end
      end

      context 'when subscription was already billed earlier the same day' do
        let(:timestamp) { Time.current }

        before { create(:fee, subscription:) }

        context 'when plan has no minimum commitment' do
          it 'does not create any subscription fees' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.subscription_kind.count).to eq(0)
              expect(invoice.invoice_subscriptions.count).to eq(1)
              expect(invoice.invoice_subscriptions.first.recurring).to be_falsey
            end
          end

          it 'does create a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          it 'does not create any subscription fees' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.subscription_kind.count).to eq(0)
              expect(invoice.invoice_subscriptions.count).to eq(1)
              expect(invoice.invoice_subscriptions.first.recurring).to be_falsey
            end
          end

          it 'does not create a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end
      end

      context 'when subscription started in the past' do
        let(:created_at) { timestamp }

        it 'creates charge fees' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.fees.charge_kind.count).to eq(1)
          end
        end
      end

      context 'when subscription started on creation day' do
        it 'does not create any charge fees' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice).to have_empty_charge_fees
          end
        end
      end

      context 'when subscription is an upgrade' do
        let(:timestamp) { Time.zone.parse('30 Sep 2022 00:31:00') }
        let(:started_at) { Time.zone.parse('12 Aug 2022 00:31:00') }
        let(:terminated_at) { timestamp - 2.days }
        let(:previous_plan) { create(:plan, amount_cents: 10_000, interval: :yearly, pay_in_advance: true) }

        let(:previous_subscription) do
          create(
            :subscription,
            plan: previous_plan,
            subscription_at: started_at.to_date,
            started_at:,
            status: :terminated,
            terminated_at:
          )
        end

        let(:subscription) do
          create(
            :subscription,
            plan:,
            previous_subscription:,
            subscription_at: started_at.to_date,
            started_at: terminated_at + 1.day,
            created_at: terminated_at + 1.day
          )
        end

        context 'when plan has no minimum commitment' do
          it 'creates pro-rated subscription fee and no charge fees' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice).to be_pending
              expect(invoice.fees.subscription_kind.count).to eq(1)
              expect(invoice).to have_empty_charge_fees

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                to_datetime: match_datetime(subscription.started_at.end_of_month),
                from_datetime: match_datetime(subscription.started_at.beginning_of_day)
              )
            end
          end

          it 'does not create a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          it 'creates pro-rated subscription fee and no charge fees' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice).to be_pending
              expect(invoice.fees.subscription_kind.count).to eq(1)
              expect(invoice).to have_empty_charge_fees

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                to_datetime: match_datetime(subscription.started_at.end_of_month),
                from_datetime: match_datetime(subscription.started_at.beginning_of_day)
              )
            end
          end

          it 'does not creates a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end
      end

      context 'when subscription is terminated after an upgrade' do
        let(:next_subscription) do
          create(
            :subscription,
            plan: next_plan,
            subscription_at: started_at.to_date,
            started_at: terminated_at,
            status: :active,
            billing_time: :calendar,
            previous_subscription: subscription,
            customer: subscription.customer
          )
        end

        let(:started_at) { DateTime.parse('07 Mar 2022') }
        let(:terminated_at) { DateTime.parse('17 Oct 2022 12:35:12') }
        let(:timestamp) { DateTime.parse('17 Oct 2022') }

        let(:subscription) do
          create(
            :subscription,
            plan:,
            subscription_at: started_at.to_date,
            started_at:,
            status: :terminated,
            terminated_at:,
            billing_time: :calendar
          )
        end

        let(:next_plan) { create(:plan, interval: :monthly, amount_cents: 2000) }

        before { next_subscription }

        context 'when plan has no minimum commitment' do
          it 'creates only the charge fees' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.subscription_kind.count).to eq(0)
              expect(invoice.fees.charge_kind.count).to eq(1)

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                charges_from_datetime: match_datetime(DateTime.parse('2022-10-01 00:00:00')),
                charges_to_datetime: match_datetime(terminated_at)
              )
            end
          end

          it 'does not creates a minimum commitment fee' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.fees.commitment_kind.count).to eq(0)
            end
          end
        end

        context 'when plan has minimum commitment' do
          before do
            create(:commitment, :minimum_commitment, plan:, amount_cents: 10_000)
          end

          context 'when plan has no minimum commitment' do
            it 'creates only the charge fees' do
              result = invoice_service.call

              aggregate_failures do
                expect(result).to be_success

                expect(invoice.fees.subscription_kind.count).to eq(0)
                expect(invoice.fees.charge_kind.count).to eq(1)

                invoice_subscription = invoice.invoice_subscriptions.first
                expect(invoice_subscription).to have_attributes(
                  charges_from_datetime: match_datetime(DateTime.parse('2022-10-01 00:00:00')),
                  charges_to_datetime: match_datetime(terminated_at)
                )
              end
            end

            it 'does not creates a minimum commitment fee' do
              result = invoice_service.call

              aggregate_failures do
                expect(result).to be_success

                expect(invoice.fees.commitment_kind.count).to eq(0)
              end
            end
          end
        end
      end
    end

    context 'when billed yearly' do
      let(:timestamp) { Time.zone.now.beginning_of_year }
      let(:interval) { 'yearly' }

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(invoice.subscriptions.first).to eq(subscription)
          expect(invoice.fees.subscription_kind.count).to eq(1)
          expect(invoice.fees.charge_kind.count).to eq(1)

          invoice_subscription = invoice.invoice_subscriptions.first
          expect(invoice_subscription).to have_attributes(
            to_datetime: match_datetime((timestamp - 1.day).end_of_day),
            from_datetime: match_datetime((timestamp - 1.year).beginning_of_day)
          )
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Jun 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2020').to_date }
        let(:subscription_at) { started_at }
        let(:billing_time) { :anniversary }

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.subscriptions.first).to eq(subscription)
            expect(invoice.fees.subscription_kind.count).to eq(1)
            expect(invoice.fees.charge_kind.count).to eq(1)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime(DateTime.parse('2022-06-05 23:59:59')),
              from_datetime: match_datetime(DateTime.parse('2021-06-06 00:00:00'))
            )
          end
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'updates the invoice accordingly' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.subscriptions.first).to eq(subscription)
              expect(invoice.fees.subscription_kind.count).to eq(1)
              expect(invoice).to have_empty_charge_fees # Because we didn't fake usage events

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                to_datetime: match_datetime(DateTime.parse('2023-06-05 23:59:59')),
                from_datetime: match_datetime(DateTime.parse('2022-06-06 00:00:00'))
              )
            end
          end
        end
      end

      context 'when billed yearly on first year' do
        let(:timestamp) { DateTime.parse(started_at.to_s).end_of_year + 1.day }
        let(:started_at) { Time.zone.today - 3.months }

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.subscriptions.first).to eq(subscription)
            expect(invoice.fees.subscription_kind.count).to eq(1)
            expect(invoice.fees.charge_kind.count).to eq(1)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime((timestamp - 1.day).end_of_day),
              from_datetime: match_datetime(subscription.subscription_at.beginning_of_day)
            )
          end
        end
      end
    end

    context 'when billed quarterly' do
      let(:timestamp) { Time.zone.now.beginning_of_year }
      let(:started_at) { Time.zone.now.beginning_of_year - 2.years }
      let(:interval) { 'quarterly' }

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(invoice.subscriptions.first).to eq(subscription)
          expect(invoice.fees.subscription_kind.count).to eq(1)
          expect(invoice.fees.charge_kind.count).to eq(1)

          invoice_subscription = invoice.invoice_subscriptions.first
          expect(invoice_subscription).to have_attributes(
            to_datetime: match_datetime((timestamp - 1.day).end_of_day),
            from_datetime: match_datetime((timestamp - 2.days).beginning_of_quarter.beginning_of_day),
            charges_to_datetime: match_datetime((timestamp - 1.day).end_of_day),
            charges_from_datetime: match_datetime((timestamp - 2.days).beginning_of_quarter.beginning_of_day)
          )
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Jun 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2020').to_date }
        let(:subscription_at) { started_at }
        let(:billing_time) { :anniversary }

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.subscriptions.first).to eq(subscription)
            expect(invoice.fees.subscription_kind.count).to eq(1)
            expect(invoice.fees.charge_kind.count).to eq(1)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime(DateTime.parse('2022-06-05 23:59:59')),
              from_datetime: match_datetime(DateTime.parse('2022-03-06 00:00:00')),
              charges_to_datetime: match_datetime(DateTime.parse('2022-06-05 23:59:59')),
              charges_from_datetime: match_datetime(DateTime.parse('2022-03-06 00:00:00'))
            )
          end
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }
          let(:old_invoice_subscription) { create(:invoice_subscription, invoice: old_invoice, subscription:) }
          let(:old_invoice) do
            create(
              :invoice,
              created_at: started_at - 3.months,
              customer: subscription.customer,
              organization: plan.organization
            )
          end

          before { old_invoice_subscription }

          it 'updates the invoice accordingly' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(invoice.subscriptions.first).to eq(subscription)
              expect(invoice.fees.subscription_kind.count).to eq(1)
              expect(invoice.fees.charge_kind.count).to eq(1)

              invoice_subscription = invoice.invoice_subscriptions.first
              expect(invoice_subscription).to have_attributes(
                to_datetime: match_datetime(DateTime.parse('2022-09-05 23:59:59')),
                from_datetime: match_datetime(DateTime.parse('2022-06-06 00:00:00')),
                charges_to_datetime: match_datetime(DateTime.parse('2022-06-05 23:59:59')),
                charges_from_datetime: match_datetime(DateTime.parse('2022-03-06 00:00:00'))
              )
            end
          end
        end
      end

      context 'when billed quarterly on first billing day' do
        let(:timestamp) { DateTime.parse('01 Jan 2022') }
        let(:started_at) { DateTime.parse('12 Nov 2021').to_date }
        let(:subscription_at) { started_at }

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.subscriptions.first).to eq(subscription)
            expect(invoice.fees.subscription_kind.count).to eq(1)
            expect(invoice.fees.charge_kind.count).to eq(1)

            invoice_subscription = invoice.invoice_subscriptions.first
            expect(invoice_subscription).to have_attributes(
              to_datetime: match_datetime((timestamp - 1.day).end_of_day),
              from_datetime: match_datetime(subscription.subscription_at.beginning_of_day),
              charges_to_datetime: match_datetime((timestamp - 1.day).end_of_day),
              charges_from_datetime: match_datetime(subscription.subscription_at.beginning_of_day)
            )
          end
        end
      end
    end

    context 'with credit' do
      let(:credit_note) do
        create(
          :credit_note,
          customer: subscription.customer,
          total_amount_cents: 10,
          total_amount_currency: plan.amount_currency,
          balance_amount_cents: 10,
          balance_amount_currency: plan.amount_currency,
          credit_amount_cents: 10,
          credit_amount_currency: plan.amount_currency
        )
      end

      before { credit_note }

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.fees_amount_cents).to eq(100)
          expect(result.invoice.taxes_amount_cents).to eq(20)
          expect(result.invoice.total_amount_cents).to eq(110)
          expect(result.invoice.credits.count).to eq(1)

          credit = result.invoice.credits.first
          expect(credit.credit_note).to eq(credit_note)
          expect(credit.amount_cents).to eq(10)
        end
      end
    end

    context 'with applied prepaid credits' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:wallet) { create(:wallet, customer: subscription.customer, balance: '0.30', credits_balance: '0.30') }

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      before { wallet }

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_datetime'])
            .to eq (timestamp - 1.day).end_of_day.as_json
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to eq (timestamp - 1.month).beginning_of_day.as_json
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
          expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(100)
          expect(result.invoice.taxes_amount_cents).to eq(20)
          expect(result.invoice.total_amount_cents).to eq(90)
          expect(result.invoice.wallet_transactions.count).to eq(1)
        end
      end

      it 'updates wallet balance' do
        invoice_service.call

        expect(wallet.reload.balance).to eq(0.0)
      end

      context 'when invoice amount in cents is zero' do
        let(:applied_coupon) do
          create(
            :applied_coupon,
            customer: subscription.customer,
            amount_cents: 120,
            amount_currency: plan.amount_currency
          )
        end

        before { applied_coupon }

        it 'does not create any wallet transactions' do
          result = invoice_service.call

          expect(result.invoice.wallet_transactions.exists?).to be(false)
        end
      end
    end
  end
end
