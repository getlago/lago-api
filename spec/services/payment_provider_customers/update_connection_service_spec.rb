# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::UpdateConnectionService do
  subject(:update_service) { described_class.new(payment_provider_customer:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:params) { {} }

  describe "#call" do
    subject(:result) { update_service.call }

    context "when payment provider customer is not found" do
      let(:payment_provider_customer) { nil }
      let(:params) { {code: "new_code"} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("payment_provider_customer_not_found")
      end
    end

    context "with a non-stripe connection" do
      let(:payment_provider_customer) { create(:adyen_customer, organization:, customer:, code: "old_code") }

      context "when updating the code" do
        let(:params) { {code: "new_code"} }

        it "updates the code" do
          expect { update_service.call }
            .to change { payment_provider_customer.reload.code }
            .from("old_code")
            .to("new_code")
        end

        it "returns the payment provider customer" do
          expect(result).to be_success
          expect(result.payment_provider_customer).to eq(payment_provider_customer)
        end
      end

      context "when provider payment methods are also provided" do
        let(:params) { {code: "new_code", provider_payment_methods: %w[card]} }

        it "updates the code and ignores the provider payment methods" do
          expect(result).to be_success
          expect(payment_provider_customer.reload.code).to eq("new_code")
        end

        it "does not create a stripe connection" do
          expect { update_service.call }
            .not_to change(PaymentProviderCustomers::StripeCustomer, :count)
        end
      end
    end

    context "with a stripe connection" do
      let(:payment_provider_customer) do
        create(:stripe_customer, organization:, customer:, code: "old_code", provider_payment_methods: %w[card])
      end

      context "when updating both code and provider payment methods" do
        let(:params) { {code: "new_code", provider_payment_methods: %w[card sepa_debit]} }

        it "updates the code" do
          expect { update_service.call }
            .to change { payment_provider_customer.reload.code }.from("old_code").to("new_code")
        end

        it "updates the provider payment methods" do
          expect { update_service.call }
            .to change { payment_provider_customer.reload.provider_payment_methods }
            .from(%w[card])
            .to(%w[card sepa_debit])
        end
      end

      context "when the provider payment methods are invalid" do
        let(:params) { {code: "new_code", provider_payment_methods: %w[invalid_method]} }

        it "returns a validation failure" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
        end

        it "does not update the code" do
          expect { update_service.call }.not_to change { payment_provider_customer.reload.code }
        end
      end
    end
  end
end
