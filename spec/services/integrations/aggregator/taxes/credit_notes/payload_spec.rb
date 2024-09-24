# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Taxes::CreditNotes::Payload do
  subject(:service_call) { payload.body }

  let(:payload) { described_class.new(integration:, customer:, integration_customer:, credit_note:) }
  let(:integration) { create(:anrok_integration, organization:) }
  let(:integration_customer) { create(:anrok_customer, integration:, customer:, external_customer_id: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:add_on) { create(:add_on, organization:) }
  let(:add_on_two) { create(:add_on, organization:) }
  let(:current_time) { Time.current }

  let(:integration_collection_mapping1) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :fallback_item,
      settings: {external_id: '1', external_account_code: '11', external_name: ''}
    )
  end
  let(:integration_mapping_add_on) do
    create(
      :netsuite_mapping,
      integration:,
      mappable_type: 'AddOn',
      mappable_id: add_on.id,
      settings: {external_id: 'm1', external_account_code: 'm11', external_name: ''}
    )
  end

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:
    )
  end
  let(:fee_add_on) do
    create(
      :fee,
      invoice:,
      add_on:,
      created_at: current_time - 3.seconds,
      amount_cents: 200,
      precise_amount_cents: 200
    )
  end
  let(:fee_add_on_two) do
    create(
      :fee,
      invoice:,
      add_on: add_on_two,
      created_at: current_time - 2.seconds,
      amount_cents: 200,
      precise_amount_cents: 200,
      precise_coupons_amount_cents: 20
    )
  end
  let(:credit_note) do
    create(
      :credit_note,
      customer:,
      invoice:,
      status: 'finalized',
      organization:
    )
  end

  let(:credit_note_item1) do
    create(:credit_note_item, credit_note:, fee: fee_add_on, amount_cents: 190)
  end
  let(:credit_note_item2) do
    create(:credit_note_item, credit_note:, fee: fee_add_on_two, amount_cents: 180)
  end

  let(:body) do
    [
      {
        'id' => "cn_#{credit_note.id}",
        'issuing_date' => credit_note.issuing_date,
        'currency' => credit_note.currency,
        'contact' => {
          'external_id' => customer.external_id,
          'name' => customer.name,
          'address_line_1' => customer.address_line1,
          'city' => customer.city,
          'zip' => customer.zipcode,
          'country' => customer.country,
          'taxable' => false,
          'tax_number' => nil
        },
        'fees' => [
          {
            'item_id' => fee_add_on.item_id,
            'item_code' => 'm1',
            'amount_cents' => -190
          },
          {
            'item_id' => fee_add_on_two.item_id,
            'item_code' => '1',
            'amount_cents' => -162
          }
        ]
      }
    ]
  end

  before do
    integration_customer
    integration_collection_mapping1
    integration_mapping_add_on
    fee_add_on
    fee_add_on_two
    credit_note_item1
    credit_note_item2
  end

  describe '#body' do
    it 'returns payload' do
      expect(service_call).to eq(body)
    end
  end
end
