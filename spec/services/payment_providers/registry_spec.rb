# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Registry do
  describe ".new_instance" do
    %i[adyen cashfree gocardless flutterwave moneyhash stripe].each do |provider|
      context "with create_customer action" do
        let(:action) { :create_customer }

        let(:customer) { create(:customer) }
        let(:payment_provider_id) { SecureRandom.uuid }
        let(:params) { {} }

        it "returns a #{provider} service instance" do
          instance = described_class.new_instance(provider, action, customer:, payment_provider_id:, params:)
          expect(instance).to be_a("PaymentProviders::#{provider.capitalize}::Customers::CreateService".constantize)
        end
      end

      context "with manage_customer action" do
        let(:action) { :manage_customer }

        let(:provider_customer) { create(:"#{provider}_customer") }

        it "returns a #{provider} service instance" do
          instance = described_class.new_instance(provider, action, provider_customer)
          expect(instance).to be_a("PaymentProviderCustomers::#{provider.capitalize}Service".constantize)
        end
      end

      context "with create_payment action" do
        let(:action) { :create_payment }

        let(:payment) { create(:payment) }
        let(:reference) { SecureRandom.uuid }
        let(:metadata) { {} }

        it "returns a #{provider} service instance or raises an error" do
          if provider == :flutterwave
            expect { described_class.new_instance(provider, action, payment:, reference:, metadata:) }
              .to raise_error(NotImplementedError)
          else
            instance = described_class.new_instance(provider, action, payment:, reference:, metadata:)
            expect(instance).to be_a("PaymentProviders::#{provider.capitalize}::Payments::CreateService".constantize)
          end
        end
      end

      context "with manage_invoice_payment action" do
        let(:action) { :manage_invoice_payment }

        let(:invoice) { create(:invoice) }

        it "returns a #{provider} service instance" do
          instance = described_class.new_instance(provider, action, invoice)
          expect(instance).to be_a("Invoices::Payments::#{provider.capitalize}Service".constantize)
        end
      end

      context "with manage_payment_request_payment action" do
        let(:action) { :manage_payment_request_payment }

        let(:payment_request) { create(:payment_request) }

        it "returns a #{provider} service instance" do
          instance = described_class.new_instance(provider, action, payment_request)
          expect(instance).to be_a("PaymentRequests::Payments::#{provider.capitalize}Service".constantize)
        end
      end

      context "with an invalid action" do
        let(:action) { :invalid_action }

        it "raises a not implemented error" do
          expect { described_class.new_instance(provider, action) }
            .to raise_error(NotImplementedError)
        end
      end
    end

    context "with an unknown provider" do
      it "raises a not implemented error" do
        expect { described_class.new_instance(:unknown_provider, :manage_invoice_payment) }
          .to raise_error(NotImplementedError)
      end
    end
  end

  describe ".register" do
    let(:actions) { {create_customer: "CreateCustomer"} }

    around do |example|
      previous_providers = described_class.providers.dup
      described_class.providers = {}
      example.run
      described_class.providers = previous_providers
    end

    it "registers a provider" do
      expect { described_class.register(:new_provider, actions) }.not_to raise_error
    end

    context "with invalid actions" do
      let(:actions) { {invalid_action: "InvalidAction"} }

      it "raises an argument error" do
        expect { described_class.register(:new_provider, actions) }
          .to raise_error(ArgumentError, "Invalid actions")
      end
    end

    context "when provider is already registered" do
      let(:provider) { :existing_provider }

      before { described_class.register(provider, actions) }

      it "raises an argument error" do
        expect { described_class.register(provider, actions) }
          .to raise_error(ArgumentError, "existing_provider already registered")
      end

      context "when ignoring existing provider" do
        it "does not raise an error" do
          expect { described_class.register(provider, actions, on_conflict: :ignore) }.not_to raise_error
        end
      end

      context "when replacing existing provider" do
        let(:new_actions) { {create_customer: "NewCreateCustomer", manage_customer: "ManageCustomer"} }

        it "does not raise an error" do
          expect { described_class.register(provider, new_actions, on_conflict: :replace) }.not_to raise_error

          expect(described_class.providers[provider]).to eq(new_actions)
        end
      end

      context "when merging with existing provider" do
        let(:new_actions) { {manage_customer: "ManageCustomer"} }

        it "does not raise an error" do
          expect { described_class.register(provider, new_actions, on_conflict: :merge) }.not_to raise_error

          expect(described_class.providers[provider]).to eq(actions.merge(new_actions))
        end
      end
    end
  end
end
