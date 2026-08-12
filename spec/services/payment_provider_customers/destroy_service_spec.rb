# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::DestroyService do
  subject(:destroy_service) { described_class.new(payment_provider_customer:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:payment_provider_customer) do
    create(:stripe_customer, organization:, customer:, is_default: true)
  end

  before { payment_provider_customer }

  describe "#call" do
    subject(:result) { destroy_service.call }

    context "when payment provider customer is not found" do
      let(:payment_provider_customer) { nil }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("payment_provider_customer_not_found")
      end
    end

    context "with a payment provider customer" do
      it "sets the payment provider customer as NOT default" do
        expect { destroy_service.call }
          .to change { payment_provider_customer.reload.is_default }
          .from(true)
          .to(false)
      end

      it "soft deletes the payment provider customer" do
        freeze_time do
          expect { destroy_service.call }
            .to change { payment_provider_customer.reload.deleted_at }.from(nil).to(Time.current)
        end
      end

      it "returns the payment provider customer" do
        expect(result).to be_success
        expect(result.payment_provider_customer).to eq(payment_provider_customer)
      end

      context "with associated payment methods" do
        let(:payment_method) do
          create(:payment_method, organization:, customer:, payment_provider_customer:)
        end

        before { payment_method }

        it "soft deletes the associated payment methods" do
          expect { destroy_service.call }
            .to change { payment_method.reload.deleted_at }.from(nil)
        end
      end

      context "when the connection is the customer's active provider" do
        let(:customer) do
          create(:customer, organization:, payment_provider: "stripe", payment_provider_code: "stripe_1")
        end

        it "clears the customer's payment provider and code" do
          destroy_service.call

          expect(customer.reload.payment_provider).to be_nil
          expect(customer.payment_provider_code).to be_nil
        end
      end

      context "when the connection is not the customer's active provider" do
        let(:customer) do
          create(:customer, organization:, payment_provider: "gocardless", payment_provider_code: "gc_1")
        end

        it "leaves the customer's payment provider untouched" do
          destroy_service.call

          expect(customer.reload.payment_provider).to eq("gocardless")
          expect(customer.payment_provider_code).to eq("gc_1")
        end
      end
    end
  end
end
