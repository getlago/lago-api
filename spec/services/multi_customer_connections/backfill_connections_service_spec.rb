# frozen_string_literal: true

require "rails_helper"

RSpec.describe MultiCustomerConnections::BackfillConnectionsService do
  subject(:result) { described_class.call(organization:, dry_run:, batch_size: 1000) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:dry_run) { false }

  describe "#call" do
    context "with a payment_provider_customer missing a code" do
      let(:provider) { create(:stripe_provider, organization:, code: "stripe_eu") }
      let(:pp_customer) { create(:stripe_customer, customer:, organization:, payment_provider: provider, code: nil) }

      before { pp_customer }

      it "sets the code from the payment provider and marks it default" do
        expect(result.summary[:payment_codes_set]).to eq(1)
        expect(result.summary[:payment_defaults_set]).to eq(1)

        pp_customer.reload
        expect(pp_customer.code).to eq("stripe_eu")
        expect(pp_customer.is_default).to be(true)
      end

      context "when the row has no payment provider" do
        let(:pp_customer) { create(:stripe_customer, customer:, organization:, payment_provider: nil, code: nil) }

        it "leaves the code nil" do
          expect(result.summary[:payment_codes_set]).to eq(0)
          expect(pp_customer.reload.code).to be_nil
        end
      end

      context "when a code is already set" do
        let(:pp_customer) { create(:stripe_customer, customer:, organization:, payment_provider: provider, code: "existing") }

        it "does not overwrite it" do
          expect(result.summary[:payment_codes_set]).to eq(0)
          expect(pp_customer.reload.code).to eq("existing")
        end
      end
    end

    context "with an integration_customer missing code and category" do
      let(:integration) { create(:netsuite_integration, organization:, code: "netsuite_eu") }
      let(:int_customer) { create(:netsuite_customer, customer:, organization:, integration:, code: nil, category: nil) }

      before { int_customer }

      it "sets code, derives category from the STI type, and marks it default" do
        expect(result.summary[:integration_codes_set]).to eq(1)
        expect(result.summary[:integration_categories_set]).to eq(1)
        expect(result.summary[:integration_defaults_set]).to eq(1)

        int_customer.reload
        expect(int_customer.code).to eq("netsuite_eu")
        expect(int_customer.category).to eq("accounting")
        expect(int_customer.is_default).to be(true)
      end
    end

    context "when the backfill already ran (idempotency)" do
      let(:provider) { create(:stripe_provider, organization:, code: "stripe_eu") }
      let(:integration) { create(:anrok_integration, organization:, code: "anrok_eu") }

      before do
        create(:stripe_customer, customer:, organization:, payment_provider: provider, code: "stripe_eu", is_default: true)
        create(:anrok_customer, customer:, organization:, integration:, code: "anrok_eu", category: "tax", is_default: true)
      end

      it "changes nothing" do
        expect(result.summary.values).to all(be_zero)
      end
    end

    context "when a customer has more than one connection in a category" do
      let(:integration_a) { create(:netsuite_integration, organization:, code: "netsuite_a") }
      let(:integration_b) { create(:xero_integration, organization:, code: "xero_b") }

      before do
        create(:netsuite_customer, customer:, organization:, integration: integration_a, code: nil, category: nil)
        create(:xero_customer, customer:, organization:, integration: integration_b, code: nil, category: nil)
      end

      it "backfills codes/categories but sets no default and records a conflict" do
        expect(result.summary[:integration_codes_set]).to eq(2)
        expect(result.summary[:integration_categories_set]).to eq(2)
        expect(result.summary[:integration_defaults_set]).to eq(0)
        expect(result.summary[:integration_default_conflicts]).to eq(1)

        expect(IntegrationCustomers::BaseCustomer.where(customer:, is_default: true)).to be_empty
      end
    end

    context "with dry_run: true" do
      let(:dry_run) { true }
      let(:provider) { create(:stripe_provider, organization:, code: "stripe_eu") }
      let(:pp_customer) { create(:stripe_customer, customer:, organization:, payment_provider: provider, code: nil) }

      before { pp_customer }

      it "reports what would change without persisting" do
        expect(result.summary[:payment_codes_set]).to eq(1)
        expect(result.summary[:payment_defaults_set]).to eq(1)

        pp_customer.reload
        expect(pp_customer.code).to be_nil
        expect(pp_customer.is_default).to be(false)
      end
    end

    context "when a connection belongs to another organization" do
      let(:other_org) { create(:organization) }
      let(:other_customer) { create(:customer, organization: other_org) }
      let(:provider) { create(:stripe_provider, organization: other_org, code: "stripe_other") }

      before { create(:stripe_customer, customer: other_customer, organization: other_org, payment_provider: provider, code: nil) }

      it "is not touched" do
        expect(result.summary.values).to all(be_zero)
      end
    end
  end
end
