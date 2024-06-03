# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::CreateRecurringPayInAdvanceService do
  subject(:service) { described_class.new(subscriptions: [subscription], billing_at:) }

  let(:billing_at) { Time.current }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:invoiceable_charge) { create(:standard_charge, plan:, pay_in_advance: true, invoiceable: true) }
  let(:non_recurring_charge) { create(:standard_charge, plan:, pay_in_advance: true, invoiceable: false) }
  let(:billable_metric) { create(:unique_count_billable_metric, :recurring, organization:) }
  let(:recurring_charge) { create(:charge, billable_metric:, plan:, pay_in_advance: true, invoiceable: false, properties: {amount: '12'}) }
  let(:subscription) { create(:subscription, plan:, customer:) }

  before do
    invoiceable_charge
    non_recurring_charge
  end

  context 'when no charge is recurring' do
    it 'does not enqueue any jobs' do
      service.call
      expect(Fees::CreatePayInAdvanceJob).not_to have_been_enqueued
    end
  end

  context 'when a charge is recurring but there is no previous fees' do
    before do
      recurring_charge
    end

    it 'does not enqueue any jobs' do
      service.call
      expect(Fees::CreatePayInAdvanceJob).not_to have_been_enqueued
    end
  end

  context 'when a charge is recurring and there is a previous fee but no event associated' do
    before do
      recurring_charge
      create(:charge_fee, charge: recurring_charge, invoice: nil, subscription:, pay_in_advance_event_id: nil)
    end

    it 'enqueues a job' do
      service.call
      expect(Fees::CreatePayInAdvanceJob).not_to have_been_enqueued
    end
  end

  context 'when a charge is recurring and there is a previous fee' do
    let(:event) { create(:event) }

    before do
      recurring_charge
      create(:charge_fee, charge: recurring_charge, invoice: nil, subscription:, pay_in_advance_event_id: event.id)
    end

    it 'enqueues a job' do
      service.call
      expect(Fees::CreatePayInAdvanceJob).to have_been_enqueued.with(charge: recurring_charge, event:, billing_at:)
    end
  end
end
