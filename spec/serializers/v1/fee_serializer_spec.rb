# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::FeeSerializer do
  subject(:serializer) { described_class.new(fee, root_name: 'fee', includes: inclusion) }

  let(:fee) do
    create(
      :fee,
      properties: {
        from_datetime: Time.current,
        to_datetime: Time.current,
      },
    )
  end

  let(:inclusion) { [] }
  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes the fee' do
    aggregate_failures do
      expect(result['fee']).to include(
        'lago_id' => fee.id,
        'lago_group_id' => fee.group_id,
        'lago_invoice_id' => fee.invoice_id,
        'lago_true_up_fee_id' => fee.true_up_fee&.id,
        'lago_true_up_parent_fee_id' => fee.true_up_parent_fee_id,
        'lago_subscription_id' => fee.subscription_id,
        'external_subscription_id' => fee.subscription&.external_id,
        'lago_customer_id' => fee.customer&.id,
        'external_customer_id' => fee.customer&.external_id,
        'amount_cents' => fee.amount_cents,
        'amount_currency' => fee.amount_currency,
        'taxes_amount_cents' => fee.taxes_amount_cents,
        'taxes_rate' => fee.taxes_rate,
        'vat_amount_cents' => fee.taxes_amount_cents,
        'total_amount_cents' => fee.total_amount_cents,
        'total_amount_currency' => fee.amount_currency,
        'units' => fee.units.to_s,
        'unit_amount_cents' => fee.unit_amount_cents,
        'precise_unit_amount' => fee.precise_unit_amount.to_s,
        'pay_in_advance' => fee.subscription.plan.pay_in_advance,
        'invoiceable' => true,
        'events_count' => fee.events_count,
        'payment_status' => fee.payment_status,
        'created_at' => fee.created_at&.iso8601,
        'succeeded_at' => fee.succeeded_at&.iso8601,
        'failed_at' => fee.failed_at&.iso8601,
        'refunded_at' => fee.refunded_at&.iso8601,
      )
      expect(result['fee']['item']).to include(
        'type' => fee.fee_type,
        'code' => fee.item_code,
        'name' => fee.item_name,
        'invoice_display_name' => fee.invoice_name,
        'lago_item_id' => fee.item_id,
        'item_type' => fee.item_type,
      )

      expect(result['fee']['from_date']).not_to be_nil
      expect(result['fee']['to_date']).not_to be_nil
    end
  end

  context 'when fee is charge' do
    let(:charge) { group_property.charge }
    let(:group_property) { create(:group_property) }

    let(:fee) do
      create(
        :charge_fee,
        charge:,
        properties: {
          from_datetime: Time.current,
          to_datetime: Time.current,
        },
      )
    end

    it 'serializes the fees with dates boundaries' do
      expect(result['fee']['from_date']).not_to be_nil
      expect(result['fee']['to_date']).not_to be_nil
      expect(result['fee']['item']).to include(
        'type' => fee.fee_type,
        'code' => fee.item_code,
        'name' => fee.item_name,
        'invoice_display_name' => fee.invoice_name,
        'group_invoice_display_name' => fee.group_name,
        'lago_item_id' => fee.item_id,
        'item_type' => fee.item_type,
      )
    end
  end

  context 'when fee is add_on' do
    let(:fee) { create(:add_on_fee) }

    it 'does not serializes the fees with date boundaries' do
      expect(result['fee']['from_date']).to be_nil
      expect(result['fee']['to_date']).to be_nil
    end
  end

  context 'when fee is one_off' do
    let(:fee) { create(:one_off_fee) }

    it 'does not serializes the fees with date boundaries' do
      expect(result['fee']['from_date']).to be_nil
      expect(result['fee']['to_date']).to be_nil
    end
  end

  context 'when pay_in_advance attributes are included' do
    let(:inclusion) { %i[pay_in_advance] }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, customer:, organization:, plan:) }
    let(:charge) { create(:standard_charge, :pay_in_advance, plan:) }

    let(:event) do
      create(
        :event,
        subscription_id: subscription.id,
        organization_id: organization.id,
        customer_id: customer.id,
      )
    end

    let(:fee) do
      create(:charge_fee, pay_in_advance: true, subscription:, charge:, pay_in_advance_event_id: event.id)
    end

    it 'serializes the pay_in_advance charge attributes' do
      aggregate_failures do
        expect(result['fee']).to include(
          'lago_subscription_id' => subscription.id,
          'external_subscription_id' => subscription.external_id,
          'lago_customer_id' => customer.id,
          'external_customer_id' => customer.external_id,
          'event_transaction_id' => event.transaction_id,
          'pay_in_advance' => true,
          'invoiceable' => true,
        )
      end
    end
  end
end
