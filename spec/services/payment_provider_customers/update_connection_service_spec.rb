# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::UpdateConnectionService do
  subject(:update_service) { described_class.new(payment_provider_customer:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
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
      let(:payment_provider_customer) do
        create(:adyen_customer, organization:, customer:, code: "old_code")
      end

      context "when updating the code" do
        let(:params) { {code: "new_code"} }

        it "updates the code" do
          expect { update_service.call }
            .to change { payment_provider_customer.reload.code }.from("old_code").to("new_code")
        end

        it "returns the payment provider customer" do
          expect(result).to be_success
          expect(result.payment_provider_customer).to eq(payment_provider_customer)
        end
      end
    end

    context "with a stripe connection" do
      let(:payment_provider_customer) do
        create(:stripe_customer, organization:, customer:, code: "old_code", provider_payment_methods: %w[card])
      end

      context "when only the code is updated" do
        let(:params) { {code: "new_code"} }

        before { allow(PaymentProviders::CreateCustomerFactory).to receive(:new_instance).and_call_original }

        it "does not run the provider customer upsert" do
          update_service.call
          expect(PaymentProviders::CreateCustomerFactory).not_to have_received(:new_instance)
        end
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

        it "rolls back the code change" do
          expect { update_service.call }.not_to change { payment_provider_customer.reload.code }
        end
      end

      context "when updating sync_with_provider" do
        let(:params) { {sync_with_provider: true} }

        it "updates sync_with_provider" do
          expect { update_service.call }
            .to change { payment_provider_customer.reload.sync_with_provider }.to(true)
        end
      end

      context "when a provider customer id is provided" do
        let(:payment_provider_customer) do
          create(:stripe_customer, organization:, customer:, provider_customer_id: "cus_old", provider_payment_methods: %w[card])
        end
        let(:params) { {provider_customer_id: "cus_new"} }

        before { allow(PaymentProviderCustomers::UpdateService).to receive(:call).and_return(BaseResult.new) }

        it "updates the provider customer id" do
          expect { update_service.call }
            .to change { payment_provider_customer.reload.provider_customer_id }.from("cus_old").to("cus_new")
        end

        it "syncs the provider customer with the provider" do
          update_service.call
          expect(PaymentProviderCustomers::UpdateService).to have_received(:call).with(customer)
        end
      end

      context "when the connection has no provider_customer_id and none is provided" do
        let(:payment_provider_customer) do
          create(:stripe_customer, organization:, customer:, provider_customer_id: nil, provider_payment_methods: %w[card])
        end
        let(:params) { {provider_payment_methods: %w[card sepa_debit]} }

        it "applies the provider payment methods" do
          expect { update_service.call }
            .to change { payment_provider_customer.reload.provider_payment_methods }
            .from(%w[card]).to(%w[card sepa_debit])
        end
      end
    end
  end
end
