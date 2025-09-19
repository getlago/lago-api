# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::MoneyhashService do
  subject(:moneyhash_service) { described_class.new(moneyhash_customer) }

  let(:customer) { create(:customer, name: customer_name, organization:) }
  let(:moneyhash_provider) { create(:moneyhash_provider) }
  let(:organization) { moneyhash_provider.organization }
  let(:customer_name) { nil }

  let(:moneyhash_customer) do
    create(:moneyhash_customer, customer:, provider_customer_id: nil, payment_provider: moneyhash_provider)
  end

  describe "#create" do
    context "when provider_customer_id is already present" do
      before {
        moneyhash_customer.update(provider_customer_id: SecureRandom.uuid)
        allow(moneyhash_service).to receive(:create_moneyhash_customer) # rubocop:disable RSpec/SubjectStub
      }

      it "does not call moneyhash customers API" do
        result = moneyhash_service.create
        expect(result).to be_success
        expect(moneyhash_service).not_to have_received(:create_moneyhash_customer) # rubocop:disable RSpec/SubjectStub
      end
    end

    context "when provider_customer_id is not present" do
      let(:moneyhash_result) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/create_customer.json"))) }
      let(:checkout_url_response) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/checkout_url_response.json"))) }

      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { "#{PaymentProviders::MoneyhashProvider.api_base_url}/api/v1.1/payments/intent/" }

      before do
        allow(moneyhash_service).to receive(:create_moneyhash_customer).and_return(moneyhash_result) # rubocop:disable RSpec/SubjectStub
        allow(moneyhash_service).to receive(:deliver_success_webhook) # rubocop:disable RSpec/SubjectStub

        allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
        allow(lago_client).to receive(:post_with_response).and_return(response)
        allow(response).to receive(:body).and_return(checkout_url_response.to_json)
      end

      it "creates the moneyhash customer, checkout_url, and sends a success webhook" do
        result = moneyhash_service.create
        expect(result).to be_success
        expect(moneyhash_customer.reload.provider_customer_id).to eq(moneyhash_result["data"]["id"])
        expect(result.checkout_url).to eq("#{checkout_url_response["data"]["embed_url"]}?lago_request=generate_checkout_url")
        expect(moneyhash_service).to have_received(:create_moneyhash_customer) # rubocop:disable RSpec/SubjectStub
        expect(moneyhash_service).to have_received(:deliver_success_webhook) # rubocop:disable RSpec/SubjectStub
      end
    end

    describe "#update" do
      it "returns a success result" do
        result = moneyhash_service.update
        expect(result).to be_success
      end
    end

    describe "#update_payment_method" do
      let(:custom_fields) do
        {
          lago_mit: false,
          lago_mh_service: "Invoices::Payments::MoneyhashService",
          lago_payable_id: "b4e7e786-7716-4ca1-940d-3606ef971413",
          lago_customer_id: "36cfbd82-167d-448e-8c0b-63269347f8ac",
          lago_payable_type: "Invoice",
          lago_organization_id: "1f6edf98-9eb4-4baf-8c64-7c6be9d0b414"
        }.with_indifferent_access
      end

      let(:payment_method_id) { SecureRandom.uuid }

      let(:moneyhash_customer) do
        create(:moneyhash_customer, customer:, provider_customer_id: SecureRandom.uuid)
      end

      it "updates the payment method for existing customer" do
        result = moneyhash_service.update_payment_method(
          organization_id: organization.id,
          customer_id: customer.id,
          payment_method_id: payment_method_id,
          metadata: custom_fields
        )
        expect(result).to be_success
        expect(moneyhash_customer.reload.payment_method_id).to eq(payment_method_id)
      end

      it "deletes the payment method for existing customer" do
        moneyhash_customer.update(payment_method_id: SecureRandom.uuid)

        result = moneyhash_service.update_payment_method(
          organization_id: organization.id,
          customer_id: customer.id,
          payment_method_id: nil
        )
        expect(result).to be_success
        expect(moneyhash_customer.reload.payment_method_id).to be_nil
      end

      it "overrides the payment method for existing customer" do
        moneyhash_customer.update(payment_method_id: SecureRandom.uuid)

        result = moneyhash_service.update_payment_method(
          organization_id: organization.id,
          customer_id: customer.id,
          payment_method_id: payment_method_id,
          metadata: custom_fields
        )
        expect(result).to be_success
        expect(moneyhash_customer.reload.payment_method_id).to eq(payment_method_id)
      end

      it "returns result directly when lago_customer_id is not present" do
        custom_fields.delete("lago_customer_id")
        result = moneyhash_service.update_payment_method(
          organization_id: organization.id,
          customer_id: customer.id,
          payment_method_id: payment_method_id,
          metadata: custom_fields
        )

        expect(result).to be_success
      end

      it "returns result directly when customer is not found" do
        custom_fields["lago_customer_id"] = SecureRandom.uuid

        result = moneyhash_service.update_payment_method(
          organization_id: organization.id,
          customer_id: SecureRandom.uuid,
          payment_method_id: payment_method_id,
          metadata: custom_fields
        )

        expect(result).to be_success
      end

      it "returns a failure when moneyhash customer is not found" do
        customer = create(:customer, organization:)
        custom_fields["lago_customer_id"] = customer.id

        result = moneyhash_service.update_payment_method(
          organization_id: organization.id,
          customer_id: customer.id,
          payment_method_id: payment_method_id,
          metadata: custom_fields
        )

        expect(result).to be_failure
        expect(result.error.to_s).to eq("moneyhash_customer_not_found")
      end
    end
  end
end
