# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::PaymentIntentSucceededService, type: :service do
  subject(:event_service) { described_class.new(organization_id: organization.id, event:) }

  let(:event) { ::Stripe::Event.construct_from(JSON.parse(event_json)) }
  let(:organization) { create(:organization) }

  let(:event_json) do
    path = Rails.root.join("spec/fixtures/stripe/webhooks/payment_intent_succeeded-#{fixtures_version}.json")
    File.read(path)
  end

  before do
    allow(::Payments::SetPaymentMethodAndCreateReceiptJob).to receive(:perform_later)
      .and_invoke(->(args) { ::Payments::SetPaymentMethodAndCreateReceiptJob.perform_now(**args) })
  end

  ["2020-08-27", "2022-11-15", "2024-09-30.acacia"].each do |fixtures_version|
    context "when payment intent event (api_version: #{fixtures_version})" do
      let(:fixtures_version) { fixtures_version }
      let(:invoice) { create(:invoice, organization:) }

      it "updates the payment status and save the payment method" do
        expect_any_instance_of(Invoices::Payments::StripeService).to receive(:update_payment_status) # rubocop:disable RSpec/AnyInstance
          .with(
            organization_id: organization.id,
            status: "succeeded",
            stripe_payment: PaymentProviders::StripeProvider::StripePayment.new(
              id: "pi_3R3dvoQ8iJWBZFaM0uu1G1rx",
              status: "succeeded",
              metadata: {
                invoice_type: "one_off",
                lago_customer_id: "e4674f68-a7ba-4ce8-95e9-981f346b49d7",
                invoice_issuing_date: "2025-03-17",
                lago_invoice_id: "5ccdc601-18a5-4f22-a8e7-a53ca18e1f00"
              }
            )
          ).and_call_original

        payment = create(:payment, provider_payment_id: event.data.object.id, payable: invoice)

        stub_request(:get, %r{/v1/payment_methods/pm_1R2DFsQ8iJWBZFaMw3LLbR0r$}).and_return(
          status: 200, body: File.read(Rails.root.join("spec/fixtures/stripe/retrieve_payment_method.json"))
        )

        result = event_service.call

        expect(result).to be_success
        expect(payment.reload.provider_payment_method_id).to eq "pm_1R2DFsQ8iJWBZFaMw3LLbR0r"
        expect(payment.reload.provider_payment_method_data).to eq({
          "type" => "card",
          "brand" => "visa",
          "last4" => "4242"
        })
      end

      it "does not enqueue a payment receipt job" do
        customer = create(:customer, organization:)
        payable = create(:invoice, customer:, issuing_date: "2025-03-17", organization:)
        create(:payment, payable:, provider_payment_id: event.data.object.id)

        stub_request(:get, %r{/v1/payment_methods/pm_1R2DFsQ8iJWBZFaMw3LLbR0r$}).and_return(
          status: 200, body: File.read(Rails.root.join("spec/fixtures/stripe/retrieve_payment_method.json"))
        )

        expect { event_service.call }.not_to have_enqueued_job(PaymentReceipts::CreateJob)
      end

      context "when issue_receipts_enabled is true" do
        around { |test| lago_premium!(&test) }
        before { organization.update!(premium_integrations: %w[issue_receipts]) }

        it "enqueues a payment receipt job" do
          customer = create(:customer, organization:)
          payable = create(:invoice, customer:, issuing_date: "2025-03-17", organization:)
          create(:payment, payable:, provider_payment_id: event.data.object.id)

          stub_request(:get, %r{/v1/payment_methods/pm_1R2DFsQ8iJWBZFaMw3LLbR0r$}).and_return(
            status: 200, body: File.read(Rails.root.join("spec/fixtures/stripe/retrieve_payment_method.json"))
          )

          expect { event_service.call }.to have_enqueued_job(PaymentReceipts::CreateJob)
        end
      end
    end
  end

  context "when payment intent event for a payment request" do
    let(:event_json) do
      path = Rails.root.join("spec/fixtures/stripe/payment_intent_event_payment_request.json")
      File.read(path)
    end

    context "when issue_receipts_enabled is true" do
      around { |test| lago_premium!(&test) }
      before { organization.update!(premium_integrations: %w[issue_receipts]) }

      it "enqueues a payment receipt job" do
        expect_any_instance_of(PaymentRequests::Payments::StripeService).to receive(:update_payment_status) # rubocop:disable RSpec/AnyInstance
          .with(
            organization_id: organization.id,
            status: "succeeded",
            stripe_payment: PaymentProviders::StripeProvider::StripePayment.new(
              id: "pi_3Qu0oXQ8iJWBZFaM2cc2RG6D",
              status: "succeeded",
              metadata: {
                lago_payment_request_id: "a587e552-36bc-4334-81f2-abcbf034ad3f",
                lago_payable_type: "PaymentRequest"
              }
            )
          ).and_call_original

        payment = create(:payment, provider_payment_id: event.data.object.id)
        create(:payment_request, customer: create(:customer, organization:), payments: [payment])

        stub_request(:get, %r{/v1/payment_methods/pm_1R2DFsQ8iJWBZFaMw3LLbR0r$}).and_return(
          status: 200, body: File.read(Rails.root.join("spec/fixtures/stripe/retrieve_payment_method.json"))
        )

        expect { event_service.call }.to have_enqueued_job(PaymentReceipts::CreateJob)
      end
    end

    it "routes the event to an other service" do
      expect_any_instance_of(PaymentRequests::Payments::StripeService).to receive(:update_payment_status) # rubocop:disable RSpec/AnyInstance
        .with(
          organization_id: organization.id,
          status: "succeeded",
          stripe_payment: PaymentProviders::StripeProvider::StripePayment.new(
            id: "pi_3Qu0oXQ8iJWBZFaM2cc2RG6D",
            status: "succeeded",
            metadata: {
              lago_payment_request_id: "a587e552-36bc-4334-81f2-abcbf034ad3f",
              lago_payable_type: "PaymentRequest"
            }
          )
        ).and_call_original

      payment = create(:payment, provider_payment_id: event.data.object.id)
      create(:payment_request, customer: create(:customer, organization:), payments: [payment])

      stub_request(:get, %r{/v1/payment_methods/pm_1R2DFsQ8iJWBZFaMw3LLbR0r$}).and_return(
        status: 200, body: File.read(Rails.root.join("spec/fixtures/stripe/retrieve_payment_method.json"))
      )

      result = event_service.call

      expect(result).to be_success
      expect(payment.reload.provider_payment_method_id).to eq "pm_1R2DFsQ8iJWBZFaMw3LLbR0r"
      expect(payment.reload.provider_payment_method_data).to eq({
        "type" => "card",
        "brand" => "visa",
        "last4" => "4242"
      })
    end

    context "when payment belongs to a payment_request from another organization" do
      let(:payment_request_other_organization) do
        create(:payment_request, organization: create(:organization))
      end

      let(:payment) do
        create(:payment, payable: payment_request_other_organization, provider_payment_id: event.data.object.id)
      end

      it "returns an empty result", :aggregate_failures do
        result = event_service.call
        expect(result).to be_success
        expect(result.payment).to be_nil
      end

      it "does not update the payment_status of the payment" do
        expect { event_service.call }
          .to not_change { payment.reload.status }
      end

      it "does not enqueue a payment receipt job" do
        expect { event_service.call }.not_to have_enqueued_job(Payments::SetPaymentMethodAndCreateReceiptJob)
      end
    end
  end

  context "when payment intent event with an invalid payable type" do
    let(:event_json) do
      path = Rails.root.join("spec/fixtures/stripe/payment_intent_event_invalid_payable_type.json")
      File.read(path)
    end

    it do
      expect { event_service.call }.to raise_error(NameError, "Invalid lago_payable_type: InvalidPayableTypeName")
    end
  end
end
