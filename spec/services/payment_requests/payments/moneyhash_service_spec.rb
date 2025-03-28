# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::MoneyhashService do
  subject(:moneyhash_service) { described_class.new(payable) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:moneyhash_provider) { create(:moneyhash_provider, organization:) }
  let(:moneyhash_customer) { create(:moneyhash_customer, customer:, payment_provider: moneyhash_provider) }
  let(:payable) do
    create(
      :payment_request,
      organization:,
      customer:,
      amount_cents: 799,
      amount_currency: "USD",
      invoices: [invoice_1, invoice_2]
    )
  end

  let(:invoice_1) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  let(:invoice_2) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 599,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  let(:payment_response_json) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/recurring_mit_payment_success_response.json"))) }
  let(:provider_payment_id) { payment_response_json.dig("data", "id") }

  describe "#create" do
    before do
      moneyhash_provider
      moneyhash_customer
      moneyhash_customer.update!(payment_method_id: "test_payment_method")
    end

    context "when moneyhash customer is missing provider customer id" do
      before { moneyhash_customer.update!(provider_customer_id: nil) }

      it "returns not found failure" do
        result = moneyhash_service.create

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("moneyhash_customer")
      end
    end

    context "when payment method is missing" do
      before { moneyhash_customer.update!(payment_method_id: nil) }

      it "returns not found failure" do
        result = moneyhash_service.create

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("payment_method")
      end
    end

    context "when payment should not be processed" do
      context "when payment already succeeded" do
        before { payable.update!(payment_status: :succeeded) }

        it "returns success without payment" do
          result = moneyhash_service.create

          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context "when moneyhash provider is missing" do
        before { moneyhash_provider.destroy }

        it "returns success without payment" do
          result = moneyhash_service.create

          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end
    end

    context "when payment amount is zero" do
      before { payable.update!(amount_cents: 0) }

      it "marks payment as succeeded without processing" do
        result = moneyhash_service.create

        expect(result).to be_success
        expect(result.payment).to be_nil
        expect(payable.reload.payment_status).to eq("succeeded")
      end
    end

    context "when payment should be processed" do
      before do
        allow_any_instance_of(LagoHttpClient::Client).to receive(:post_with_response) # rubocop:disable RSpec/AnyInstance
          .and_return(OpenStruct.new(body: payment_response_json.to_json))
      end

      it "increments payment attempts, creates a payment and updates payment statuses for payable and invoices" do
        result = moneyhash_service.create

        expect(result).to be_success
        expect(result.payment).to be_present
        expect(result.payment.status).to eq("succeeded")
        expect(result.payment.provider_payment_id).to eq(provider_payment_id)
        expect(payable.reload.payment_status).to eq("succeeded")
        payable.invoices.each do |invoice|
          expect(invoice.payment_status).to eq("succeeded")
        end
      end

      context "when API request fails" do
        before do
          allow_any_instance_of(LagoHttpClient::Client).to receive(:post_with_response) # rubocop:disable RSpec/AnyInstance
            .and_raise(LagoHttpClient::HttpError.new(422, "error", "error_code"))
        end

        it "marks payment as failed" do
          result = moneyhash_service.create

          expect(result).to be_success
          expect(result.payment).to be_nil
          expect(payable.reload.payment_status).to eq("failed")
          payable.invoices.each do |invoice|
            expect(invoice.payment_status).to eq("pending")
          end
        end
      end
    end
  end

  describe "#update_payment_status" do
    let(:payment) { create(:payment, payment_provider: moneyhash_provider, provider_payment_id:, payable:, amount_cents: payable.total_amount_cents, amount_currency: payable.currency) }

    before do
      moneyhash_provider
      moneyhash_customer
      payable
      payment
      payment_response_json["data"]["custom_fields"]["lago_payable_id"] = payable.id
      payment_response_json["data"]["custom_fields"]["lago_payable_type"] = payable.class.name
    end

    context "when payment exists" do
      it "updates payment, payable and invoices status" do
        result = moneyhash_service.update_payment_status(
          organization_id: organization.id,
          provider_payment_id: payment_response_json.dig("data", "id"),
          status: payment_response_json.dig("data", "status"),
          metadata: payment_response_json.dig("data", "custom_fields")
        )

        expect(result).to be_success
        expect(result.payment.status).to eq("succeeded")
        expect(result.payment.provider_payment_id).to eq(payment_response_json.dig("data", "id"))
        expect(result.payable.payment_status).to eq("succeeded")
        [invoice_1, invoice_2].each do |invoice|
          expect(invoice.reload.payment_status).to eq("succeeded")
        end
      end
    end

    context "when payment does not exist" do
      let(:metadata) { {"lago_payable_id" => payable.id} }

      it "creates a new payment" do
        result = moneyhash_service.update_payment_status(
          organization_id: organization.id,
          provider_payment_id: "new_payment_id",
          status: "SUCCESSFUL",
          metadata:
        )

        expect(result).to be_success
        expect(result.payment).to be_present
        expect(result.payment.provider_payment_id).to eq("new_payment_id")
        expect(result.payment.status).to eq("succeeded")
        expect(result.payable.payment_status).to eq("succeeded")
        [invoice_1, invoice_2].each do |invoice|
          expect(invoice.reload.payment_status).to eq("succeeded")
        end
      end

      context "when payable is not found" do
        let(:metadata) { {"lago_payable_id" => "invalid_id"} }
        let(:moneyhash_service) { described_class.new(nil) }

        it "returns not found error" do
          result = moneyhash_service.update_payment_status(
            organization_id: organization.id,
            provider_payment_id: "new_payment_id",
            status: "SUCCESSFUL",
            metadata:
          )

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("payment_request")
        end
      end
    end

    context "when payment already succeeded" do
      before do
        payable.update!(payment_status: :succeeded)
        payment.update!(status: :succeeded)
      end

      it "does not update the status" do
        result = moneyhash_service.update_payment_status(
          organization_id: organization.id,
          provider_payment_id: payment_response_json.dig("data", "id"),
          status: "FAILED",
          metadata: payment_response_json.dig("data", "custom_fields")
        )

        expect(result).to be_success
        expect(payment.reload.status).to eq("succeeded")
        expect(payable.reload.payment_status).to eq("succeeded")
      end
    end
  end
end
