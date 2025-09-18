# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::StripeService do
  subject(:stripe_service) { described_class.new(payment_request) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:billing_entity) { organization.default_billing_entity }
  let(:stripe_payment_provider) { create(:stripe_provider, organization:, code:) }
  let(:stripe_customer) {
    create(:stripe_customer, customer:, payment_method_id: stripe_payment_method_id)
  }
  let(:stripe_payment_method_id) { "pm_123456" }
  let(:code) { "stripe_1" }

  let(:payment_request) do
    create(
      :payment_request,
      organization:,
      customer:,
      amount_cents: 799,
      amount_currency: "EUR",
      invoices:
    )
  end

  let(:invoices) { [invoice_1, invoice_2] }

  let(:invoice_1) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: "EUR",
      ready_for_payment_processing: true
    )
  end

  let(:invoice_2) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 599,
      currency: "EUR",
      ready_for_payment_processing: true
    )
  end

  describe "#generate_payment_url" do
    before do
      stripe_payment_provider
      stripe_customer

      allow(::Stripe::Checkout::Session).to receive(:create)
        .and_return({"url" => "https://example.com"})
    end

    it "generates payment url" do
      stripe_service.generate_payment_url

      expect(::Stripe::Checkout::Session)
        .to have_received(:create)
        .with(
          {
            line_items: [
              {
                quantity: 1,
                price_data: {
                  currency: invoice_1.currency.downcase,
                  unit_amount: invoice_1.total_amount_cents,
                  product_data: {name: invoice_1.number}
                }
              },
              {
                quantity: 1,
                price_data: {
                  currency: invoice_2.currency.downcase,
                  unit_amount: invoice_2.total_amount_cents,
                  product_data: {name: invoice_2.number}
                }
              }
            ],
            mode: "payment",
            success_url: stripe_payment_provider.success_redirect_url,
            customer: customer.stripe_customer.provider_customer_id,
            payment_method_types: customer.stripe_customer.provider_payment_methods,
            payment_intent_data: {
              description: "#{billing_entity.name} - Overdue invoices",
              metadata: {
                lago_customer_id: customer.id,
                lago_payable_id: payment_request.id,
                lago_payable_type: "PaymentRequest",
                payment_type: "one-time"
              }
            }
          },
          hash_including({api_key: an_instance_of(String)})
        )
    end

    context "when payment request is related to a single overdue invoice" do
      let(:invoices) { [invoice_1] }

      it "includes the invoice number in stripe data" do
        stripe_service.generate_payment_url

        expect(::Stripe::Checkout::Session)
          .to have_received(:create)
          .with(
            {
              line_items: [
                {
                  quantity: 1,
                  price_data: {
                    currency: invoice_1.currency.downcase,
                    unit_amount: invoice_1.total_amount_cents,
                    product_data: {name: invoice_1.number}
                  }
                }
              ],
              mode: "payment",
              success_url: stripe_payment_provider.success_redirect_url,
              customer: customer.stripe_customer.provider_customer_id,
              payment_method_types: customer.stripe_customer.provider_payment_methods,
              payment_intent_data: {
                description: "#{billing_entity.name} - Overdue invoices: #{invoice_1.number}",
                metadata: {
                  lago_customer_id: customer.id,
                  lago_payable_id: payment_request.id,
                  lago_payable_type: "PaymentRequest",
                  payment_type: "one-time"
                }
              }
            },
            hash_including({api_key: an_instance_of(String)})
          )
      end
    end

    context "with an error on Stripe" do
      before do
        allow(::Stripe::Checkout::Session).to receive(:create)
          .and_raise(::Stripe::InvalidRequestError.new("error", {}))
      end

      it "returns a failed result" do
        result = stripe_service.generate_payment_url

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error.third_party).to eq("Stripe")
        expect(result.error.error_message).to eq("error")
      end
    end
  end

  describe "#update_payment_status" do
    subject(:result) do
      stripe_service.update_payment_status(
        organization_id: organization.id,
        stripe_payment:,
        status:
      )
    end

    let(:status) { "succeeded" }

    let(:payment) do
      create(
        :payment,
        payable: payment_request,
        provider_payment_id: stripe_payment.id
      )
    end

    let(:stripe_payment) do
      PaymentProviders::StripeProvider::StripePayment.new(
        id: "ch_123456",
        status: "succeeded",
        metadata: {}
      )
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(SendWebhookJob).to receive(:perform_later)
      payment
    end

    it "updates the payment, payment_request and invoice payment_status" do
      expect(result).to be_success
      expect(result.payment.status).to eq(status)
      expect(result.payment.payable_payment_status).to eq("succeeded")

      expect(result.payable.reload).to be_payment_succeeded
      expect(result.payable.ready_for_payment_processing).to eq(false)

      expect(invoice_1.reload).to be_payment_succeeded
      expect(invoice_1.ready_for_payment_processing).to eq(false)
      expect(invoice_2.reload).to be_payment_succeeded
      expect(invoice_2.ready_for_payment_processing).to eq(false)

      expect(invoice_1.total_paid_amount_cents).to eq(invoice_1.total_amount_cents)
      expect(invoice_2.total_paid_amount_cents).to eq(invoice_2.total_amount_cents)
    end

    it "does not send payment requested email" do
      expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
    end

    context "when the payment request belongs to a dunning campaign" do
      let(:customer) do
        create(
          :customer,
          payment_provider_code: code,
          last_dunning_campaign_attempt: 3,
          last_dunning_campaign_attempt_at: Time.zone.now
        )
      end

      let(:payment_request) do
        create(
          :payment_request,
          organization:,
          customer:,
          amount_cents: 799,
          amount_currency: "USD",
          invoices: [invoice_1, invoice_2],
          dunning_campaign: create(:dunning_campaign)
        )
      end

      it "resets the customer dunning campaign counters" do
        expect { result && customer.reload }
          .to change(customer, :last_dunning_campaign_attempt).to(0)
          .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

        expect(result).to be_success
      end

      context "when status is failed" do
        let(:status) { "failed" }

        it "doest not reset the customer dunning campaign counters" do
          expect { result && customer.reload }
            .to not_change(customer, :last_dunning_campaign_attempt)
            .and not_change { customer.last_dunning_campaign_attempt_at&.to_i }

          expect(result).to be_success
        end
      end
    end

    context "when status is failed" do
      let(:status) { "failed" }

      it "updates the payment, payment_request and invoice status" do
        expect(result).to be_success
        expect(result.payment.status).to eq(status)
        expect(result.payment.payable_payment_status).to eq("failed")

        expect(result.payable.reload).to be_payment_failed
        expect(result.payable.ready_for_payment_processing).to eq(true)

        expect(invoice_1.reload).to be_payment_failed
        expect(invoice_1.ready_for_payment_processing).to eq(true)

        expect(invoice_2.reload).to be_payment_failed
        expect(invoice_2.ready_for_payment_processing).to eq(true)

        expect(invoice_1.total_paid_amount_cents).to eq(0)
        expect(invoice_2.total_paid_amount_cents).to eq(0)
      end

      it "sends a payment requested email" do
        expect { result }.to have_enqueued_mail(PaymentRequestMailer, :requested)
          .with(params: {payment_request:}, args: [])
      end
    end

    context "when payment_request and invoice is already payment_succeeded" do
      before do
        payment_request.payment_succeeded!
        invoice_1.payment_succeeded!
        invoice_2.payment_succeeded!
      end

      it "does not update the status of invoice, payment_request and payment" do
        expect { result }
          .to not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and not_change { payment_request.reload.payment_status }
          .and not_change { payment.reload.status }

        expect(result).to be_success
      end

      it "does not send payment requested email" do
        expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end
    end

    context "with invalid status" do
      let(:status) { "invalid-status" }

      it "does not update the payment_status of payment_request, invoice and payment" do
        expect { result }
          .to not_change { payment_request.reload.payment_status }
          .and not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and not_change { payment.reload.status }
      end

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:payable_payment_status)
        expect(result.error.messages[:payable_payment_status]).to include("value_is_invalid")
      end

      it "does not send payment requested email" do
        expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end
    end

    context "when payment is not found and it is one time payment" do
      let(:payment) { nil }
      let(:status) { "succeeded" }

      let(:stripe_payment) do
        PaymentProviders::StripeProvider::StripePayment.new(
          id: "ch_123456",
          status: "succeeded",
          metadata: {
            lago_payable_id: payment_request.id,
            lago_payable_type: "PaymentRequest",
            payment_type: "one-time"
          }
        )
      end

      before do
        stripe_payment_provider
        stripe_customer
      end

      it "creates a payment and updates payment request and invoice payment status" do
        expect(result).to be_success
        expect(result.payment.status).to eq(status)
        expect(result.payment.payable_payment_status).to eq("succeeded")

        expect(result.payable.reload).to be_payment_succeeded
        expect(result.payable.ready_for_payment_processing).to eq(false)

        expect(invoice_1.reload).to be_payment_succeeded
        expect(invoice_1.ready_for_payment_processing).to eq(false)
        expect(invoice_2.reload).to be_payment_succeeded
        expect(invoice_2.ready_for_payment_processing).to eq(false)
      end

      context "when payment request is not found" do
        let(:stripe_payment) do
          PaymentProviders::StripeProvider::StripePayment.new(
            id: "ch_123456",
            status: "succeeded",
            metadata: {
              lago_payable_id: "invalid",
              lago_payable_type: "PaymentRequest",
              payment_type: "one-time"
            }
          )
        end

        it "raises a not found failure" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("payment_request_not_found")
        end
      end
    end

    context "when the payment is found by stripe payment id" do
      let(:payment) do
        create(
          :payment,
          payable: payment_request,
          provider_payment_id: stripe_payment.id,
          status: "pending"
        )
      end

      let(:stripe_payment) do
        PaymentProviders::StripeProvider::StripePayment.new(
          id: "ch_123456",
          status: "succeeded",
          metadata: {
            lago_payable_id: payment_request.id,
            lago_payable_type: "PaymentRequest",
            payment_type: "one-time"
          }
        )
      end

      before do
        stripe_payment_provider
        stripe_customer
        payment
      end

      it "updates the payment status and related entities" do
        expect(result).to be_success
        expect(result.payment.status).to eq("succeeded")
        expect(result.payment.payable_payment_status).to eq("succeeded")

        expect(result.payable.reload).to be_payment_succeeded
        expect(result.payable.ready_for_payment_processing).to eq(false)

        expect(invoice_1.reload).to be_payment_succeeded
        expect(invoice_1.ready_for_payment_processing).to eq(false)
        expect(invoice_2.reload).to be_payment_succeeded
        expect(invoice_2.ready_for_payment_processing).to eq(false)

        expect(invoice_1.total_paid_amount_cents).to eq(invoice_1.total_amount_cents)
        expect(invoice_2.total_paid_amount_cents).to eq(invoice_2.total_amount_cents)
      end

      it "does not create a new payment" do
        expect { result }.not_to change(Payment, :count)
      end
    end

    context "when payment is not found" do
      let(:payment) { nil }
      let(:status) { "succeeded" }

      it "returns an empty result" do
        expect(result).to be_success
        expect(result.payment).to be_nil
      end

      context "with payment request id in metadata" do
        let(:stripe_payment) do
          PaymentProviders::StripeProvider::StripePayment.new(
            id: "ch_123456",
            status: "succeeded",
            metadata: {
              lago_payable_id: SecureRandom.uuid,
              lago_payable_type: "PaymentRequest"
            }
          )
        end

        it "returns an empty result" do
          expect(result).to be_success
          expect(result.payment).to be_nil
        end

        context "when the payment request is found for organization" do
          let(:stripe_payment) do
            PaymentProviders::StripeProvider::StripePayment.new(
              id: "ch_123456",
              status: "succeeded",
              metadata: {
                lago_payable_id: payment_request.id,
                lago_payable_type: "PaymentRequest"
              }
            )
          end

          before do
            stripe_customer
            stripe_payment_provider
          end

          it "creates the missing payment and updates payment_request status" do
            expect(result).to be_success
            expect(result.payment.status).to eq(status)
            expect(result.payment.payable_payment_status).to eq("succeeded")

            expect(result.payable.reload).to be_payment_succeeded
            expect(result.payable.ready_for_payment_processing).to eq(false)

            expect(invoice_1.reload).to be_payment_succeeded
            expect(invoice_1.ready_for_payment_processing).to eq(false)
            expect(invoice_2.reload).to be_payment_succeeded
            expect(invoice_2.ready_for_payment_processing).to eq(false)

            expect(payment_request.payments.count).to eq(1)
            payment = payment_request.payments.first
            expect(payment).to have_attributes(
              payable: payment_request,
              payment_provider_id: stripe_payment_provider.id,
              payment_provider_customer_id: stripe_customer.id,
              amount_cents: payment_request.total_amount_cents,
              amount_currency: payment_request.currency,
              provider_payment_id: "ch_123456",
              status: "succeeded"
            )
          end
        end
      end
    end

    context "when payment belongs to a payment_request from another company" do
      let(:payment_request_other_organization) do
        create(:payment_request, organization: create(:organization))
      end

      let(:payment) do
        create(:payment, payable: payment_request_other_organization, provider_payment_id: "ch_123456")
      end

      it "returns an empty result" do
        expect(result).to be_success
        expect(result.payment).to be_nil
      end

      it "does not update the payment_status of payment_request, invoice and payment" do
        expect { result }
          .to not_change { payment_request.reload.payment_status }
          .and not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and not_change { payment.reload.status }
      end
    end

    context "when payment's payable already has a successful payment" do
      let(:payment) { nil }

      let(:stripe_payment) do
        PaymentProviders::StripeProvider::StripePayment.new(
          id: "ch_123456",
          status: "succeeded",
          metadata: {
            lago_payable_id: payment_request.id,
            lago_payable_type: "PaymentRequest"
          }
        )
      end

      before do
        stripe_customer
        stripe_payment_provider

        payment_request.payment_succeeded!
      end

      it "returns an empty result" do
        expect(result).to be_success
        expect(result.payment).to be_nil
        expect(result.payable).to be_nil
      end
    end
  end
end
