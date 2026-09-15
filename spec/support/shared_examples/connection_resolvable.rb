# frozen_string_literal: true

# Shared coverage for ConnectionResolvable. The including spec must define `let(:resolvable)`,
# a billing object whose customer's default connections are inherited.
RSpec.shared_examples "a connection-resolvable billing object" do
  let(:resolution_customer) { resolvable.customer }
  let(:organization) { resolution_customer.organization }

  describe "#effective_payment_connection" do
    context "when the customer has a default payment connection" do
      let!(:default_connection) do
        create(:stripe_customer, customer: resolution_customer, organization:, is_default: true)
      end

      it "returns the customer default" do
        expect(resolvable.effective_payment_connection).to eq(default_connection)
      end

      context "when the object pins a specific connection" do
        let(:override_connection) { create(:gocardless_customer, customer: resolution_customer, organization:) }

        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :payment,
            behavior: :specific, payment_provider_customer: override_connection)
        end

        it "returns the override connection" do
          expect(resolvable.effective_payment_connection).to eq(override_connection)
        end
      end

      context "when the object skips the category" do
        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :payment, behavior: :skip)
        end

        it "returns nil" do
          expect(resolvable.effective_payment_connection).to be_nil
        end
      end
    end

    context "when the customer has no default payment connection" do
      it "returns nil" do
        expect(resolvable.effective_payment_connection).to be_nil
      end
    end
  end

  describe "#effective_accounting_connection" do
    context "when the customer has a default accounting connection" do
      let!(:default_connection) do
        create(:netsuite_customer, customer: resolution_customer, organization:, is_default: true)
      end

      it "returns the customer default" do
        expect(resolvable.effective_accounting_connection).to eq(default_connection)
      end

      context "when the object pins a specific connection" do
        let(:override_connection) { create(:xero_customer, customer: resolution_customer, organization:) }

        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :accounting,
            behavior: :specific, integration_customer: override_connection)
        end

        it "returns the override connection" do
          expect(resolvable.effective_accounting_connection).to eq(override_connection)
        end
      end

      context "when the object skips the category" do
        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :accounting, behavior: :skip)
        end

        it "returns nil" do
          expect(resolvable.effective_accounting_connection).to be_nil
        end
      end
    end
  end

  describe "#effective_tax_connection" do
    let!(:default_connection) do
      create(:anrok_customer, customer: resolution_customer, organization:, is_default: true)
    end

    it "returns the customer default tax connection" do
      expect(resolvable.effective_tax_connection).to eq(default_connection)
    end
  end

  describe "#effective_crm_connection" do
    let!(:default_connection) do
      create(:hubspot_customer, customer: resolution_customer, organization:, is_default: true)
    end

    it "returns the customer default crm connection" do
      expect(resolvable.effective_crm_connection).to eq(default_connection)
    end
  end
end
