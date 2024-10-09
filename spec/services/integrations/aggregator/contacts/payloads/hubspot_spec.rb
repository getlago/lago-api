# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Contacts::Payloads::Hubspot do
  let(:integration) { integration_customer.integration }
  let(:integration_customer) { FactoryBot.create(:hubspot_customer, customer:) }
  let(:customer) { create(:customer, customer_type: 'individual') }
  let(:payload) { described_class.new(integration:, customer:, integration_customer:) }
  let(:customer_link) { payload.__send__(:customer_url) }

  describe "#create_body" do
    subject(:create_body_call) { payload.create_body }

    let(:payload_body) do
      {
        'properties' => {
          'email' => customer.email,
          'firstname' => customer.firstname,
          'lastname' => customer.lastname,
          'phone' => customer.phone,
          'company' => customer.legal_name,
          'website' => customer.url,
          'lago_customer_id' => customer.id,
          'lago_customer_external_id' => customer.external_id,
          'lago_billing_email' => customer.email,
          'lago_customer_link' => customer_link
        }
      }
    end

    it 'returns the payload body' do
      expect(subject).to eq payload_body
    end
  end

  describe "#update_body" do
    subject(:update_body_call) { payload.update_body }

    let(:payload_body) do
      {
        'properties' => {
          'email' => customer.email,
          'firstname' => customer.firstname,
          'lastname' => customer.lastname,
          'phone' => customer.phone,
          'company' => customer.legal_name,
          'website' => customer.url
        }
      }
    end

    it 'returns the payload body' do
      expect(subject).to eq payload_body
    end
  end
end
