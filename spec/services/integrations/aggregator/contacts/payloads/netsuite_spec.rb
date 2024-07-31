# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Contacts::Payloads::Netsuite do
  let(:integration) { integration_customer.integration }
  let(:customer) { integration_customer.customer }
  let(:integration_customer) { FactoryBot.create(:netsuite_customer) }
  let(:subsidiary_id) { Faker::Number.number(digits: 2) }
  let(:payload) { described_class.new(integration:, customer:, integration_customer:, subsidiary_id:) }

  describe "#create_body" do
    subject(:create_body_call) { payload.create_body }

    let(:payload_body) do
      {
        'type' => 'customer',
        'isDynamic' => false,
        'columns' => {
          'companyname' => customer.name,
          'subsidiary' => subsidiary_id,
          'custentity_lago_id' => customer.id,
          'custentity_lago_sf_id' => customer.external_salesforce_id,
          'custentity_form_activeprospect_customer' => customer.name,
          'custentity_lago_customer_link' => "#{ENV["LAGO_FRONT_URL"]}/customer/#{customer.id}",
          'email' => customer.email,
          'phone' => customer.phone
        },
        'options' => {
          'ignoreMandatoryFields' => false
        }
      }
    end

    it "returns the payload body" do
      expect(subject).to eq payload_body
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
          'custentity_lago_customer_link' => "#{ENV["LAGO_FRONT_URL"]}/customer/#{customer.id}",
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
