# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Contacts::Payloads::Netsuite do
  let(:integration) { integration_customer.integration }
  let(:integration_customer) { FactoryBot.create(:netsuite_customer, customer:) }
  let(:customer) { create(:customer) }
  let(:subsidiary_id) { Faker::Number.number(digits: 2) }
  let(:payload) { described_class.new(integration:, customer:, integration_customer:, subsidiary_id:) }
  let(:customer_link) { payload.__send__(:customer_url) }

  describe "#create_body" do
    subject(:create_body_call) { payload.create_body }

    let(:payload_body) do
      {
        'type' => 'customer',
        'isDynamic' => true,
        'columns' => {
          'companyname' => customer.name,
          'subsidiary' => subsidiary_id,
          'custentity_lago_id' => customer.id,
          'custentity_lago_sf_id' => customer.external_salesforce_id,
          'custentity_form_activeprospect_customer' => customer.name,
          'custentity_lago_customer_link' => customer_link,
          'email' => customer.email,
          'phone' => customer.phone
        },
        'options' => {
          'ignoreMandatoryFields' => false
        },
        'lines' => lines
      }
    end

    context 'when legacy script is false' do
      context 'when shipping address is present' do
        context 'when shipping address is not the same as billing address' do
          let(:customer) { create(:customer, :with_shipping_address) }

          let(:lines) do
            [
              {
                'lineItems' => [
                  {
                    'defaultshipping' => false,
                    'defaultbilling' => true,
                    'subObjectId' => 'addressbookaddress',
                    'subObject' => {
                      'addr1' => customer.address_line1,
                      'addr2' => customer.address_line2,
                      'city' => customer.city,
                      'zip' => customer.zipcode,
                      'state' => customer.state,
                      'country' => customer.country
                    }
                  },
                  {
                    'defaultshipping' => true,
                    'defaultbilling' => false,
                    'subObjectId' => 'addressbookaddress',
                    'subObject' => {
                      'addr1' => customer.shipping_address_line1,
                      'addr2' => customer.shipping_address_line2,
                      'city' => customer.shipping_city,
                      'zip' => customer.shipping_zipcode,
                      'state' => customer.shipping_state,
                      'country' => customer.shipping_country
                    }
                  }
                ],
                'sublistId' => 'addressbook'
              }
            ]
          end

          it 'returns the payload body' do
            expect(subject).to eq payload_body
          end
        end

        context 'when shipping address is the same as billing address' do
          let(:customer) { create(:customer, :with_same_billing_and_shipping_address) }

          let(:lines) do
            [
              {
                'lineItems' => [
                  {
                    'defaultshipping' => true,
                    'defaultbilling' => true,
                    'subObjectId' => 'addressbookaddress',
                    'subObject' => {
                      'addr1' => customer.address_line1,
                      'addr2' => customer.address_line2,
                      'city' => customer.city,
                      'zip' => customer.zipcode,
                      'state' => customer.state,
                      'country' => customer.country
                    }
                  }
                ],
                'sublistId' => 'addressbook'
              }
            ]
          end

          it 'returns the payload body' do
            expect(subject).to eq payload_body
          end
        end
      end

      context 'when shipping address is not present' do
        let(:lines) do
          [
            {
              'lineItems' => [
                {
                  'defaultshipping' => true,
                  'defaultbilling' => true,
                  'subObjectId' => 'addressbookaddress',
                  'subObject' => {
                    'addr1' => customer.address_line1,
                    'addr2' => customer.address_line2,
                    'city' => customer.city,
                    'zip' => customer.zipcode,
                    'state' => customer.state,
                    'country' => customer.country
                  }
                }
              ],
              'sublistId' => 'addressbook'
            }
          ]
        end

        context 'when billing address is present' do
          let(:customer) { create(:customer) }

          it 'returns the payload body' do
            expect(subject).to eq payload_body
          end
        end

        context 'when billing address is not present' do
          let(:customer) do
            create(
              :customer,
              address_line1: nil,
              address_line2: nil,
              city: nil,
              zipcode: nil,
              state: nil,
              country: nil
            )
          end

          it 'returns the payload body without lines' do
            expect(subject).to eq payload_body.except('lines')
          end
        end
      end
    end

    context 'when legacy script is true' do
      before { integration.legacy_script = true }

      context 'when shipping address is present' do
        context 'when shipping address is not the same as billing address' do
          let(:customer) { create(:customer, :with_shipping_address) }

          let(:lines) do
            [
              {
                'lineItems' => [
                  {
                    'defaultshipping' => false,
                    'defaultbilling' => true,
                    'subObjectId' => 'addressbookaddress',
                    'subObject' => {
                      'addr1' => customer.address_line1,
                      'addr2' => customer.address_line2,
                      'city' => customer.city,
                      'zip' => customer.zipcode,
                      'state' => customer.state,
                      'country' => customer.country
                    }
                  },
                  {
                    'defaultshipping' => true,
                    'defaultbilling' => false,
                    'subObjectId' => 'addressbookaddress',
                    'subObject' => {
                      'addr1' => customer.shipping_address_line1,
                      'addr2' => customer.shipping_address_line2,
                      'city' => customer.shipping_city,
                      'zip' => customer.shipping_zipcode,
                      'state' => customer.shipping_state,
                      'country' => customer.shipping_country
                    }
                  }
                ],
                'sublistId' => 'addressbook'
              }
            ]
          end

          it 'returns the payload body without lines' do
            expect(subject).to eq payload_body.except('lines')
          end
        end

        context 'when shipping address is the same as billing address' do
          let(:customer) { create(:customer, :with_same_billing_and_shipping_address) }

          let(:lines) do
            [
              {
                'lineItems' => [
                  {
                    'defaultshipping' => true,
                    'defaultbilling' => true,
                    'subObjectId' => 'addressbookaddress',
                    'subObject' => {
                      'addr1' => customer.address_line1,
                      'addr2' => customer.address_line2,
                      'city' => customer.city,
                      'zip' => customer.zipcode,
                      'state' => customer.state,
                      'country' => customer.country
                    }
                  }
                ],
                'sublistId' => 'addressbook'
              }
            ]
          end

          it 'returns the payload body without lines' do
            expect(subject).to eq payload_body.except('lines')
          end
        end
      end

      context 'when shipping address is not present' do
        let(:lines) do
          [
            {
              'lineItems' => [
                {
                  'defaultshipping' => true,
                  'defaultbilling' => true,
                  'subObjectId' => 'addressbookaddress',
                  'subObject' => {
                    'addr1' => customer.address_line1,
                    'addr2' => customer.address_line2,
                    'city' => customer.city,
                    'zip' => customer.zipcode,
                    'state' => customer.state,
                    'country' => customer.country
                  }
                }
              ],
              'sublistId' => 'addressbook'
            }
          ]
        end

        context 'when billing address is present' do
          let(:customer) { create(:customer) }

          it 'returns the payload body without lines' do
            expect(subject).to eq payload_body.except('lines')
          end
        end

        context 'when billing address is not present' do
          let(:customer) do
            create(
              :customer,
              address_line1: nil,
              address_line2: nil,
              city: nil,
              zipcode: nil,
              state: nil,
              country: nil
            )
          end

          it 'returns the payload body without lines' do
            expect(subject).to eq payload_body.except('lines')
          end
        end
      end
    end
  end

  describe "#update_body" do
    subject(:update_body_call) { payload.update_body }

    let(:payload_body) do
      {
        'type' => 'customer',
        'recordId' => integration_customer.external_customer_id,
        'values' => {
          'companyname' => customer.name,
          'subsidiary' => integration_customer.subsidiary_id,
          'custentity_lago_sf_id' => customer.external_salesforce_id,
          'custentity_form_activeprospect_customer' => customer.name, # TODO: Will be removed
          'custentity_lago_customer_link' => customer_link,
          'email' => customer.email,
          'phone' => customer.phone
        },
        'options' => {
          'isDynamic' => false
        }
      }
    end

    it "returns the payload body" do
      expect(subject).to eq payload_body
    end
  end
end
