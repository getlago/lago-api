# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingObjectConnections::AttachToResourceService do
  subject(:result) { described_class.call(resource:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:resource) { create(:wallet, customer:, organization:) }

  let(:stripe_connection) { create(:stripe_customer, customer:, code: "stripe_us") }
  let(:netsuite_connection) { create(:netsuite_customer, customer:, code: "netsuite_main") }

  describe "#call" do
    context "when the connections key is absent" do
      let(:params) { {name: "whatever"} }

      it "does not touch any row" do
        expect { result }.not_to change(BillingObjectConnection, :count)
        expect(result).to be_success
      end
    end

    context "when connections is empty" do
      let(:params) { {connections: {}} }

      it "does not touch any row" do
        expect { result }.not_to change(BillingObjectConnection, :count)
        expect(result).to be_success
      end
    end

    context "with a specific payment connection" do
      let(:params) { {connections: {payment: {code: "stripe_us"}}} }

      before { stripe_connection }

      it "pins the payment provider customer" do
        expect { result }.to change(BillingObjectConnection, :count).by(1)

        override = resource.billing_object_connections.sole
        expect(override).to have_attributes(
          category: "payment",
          behavior: "specific",
          organization_id: organization.id,
          payment_provider_customer_id: stripe_connection.id,
          integration_customer_id: nil
        )
      end
    end

    context "with a specific accounting connection" do
      let(:params) { {connections: {accounting: {code: "netsuite_main"}}} }

      before { netsuite_connection }

      it "pins the integration customer" do
        result

        override = resource.billing_object_connections.sole
        expect(override).to have_attributes(
          category: "accounting",
          behavior: "specific",
          integration_customer_id: netsuite_connection.id,
          payment_provider_customer_id: nil
        )
      end
    end

    context "with skip" do
      let(:params) { {connections: {tax: {behavior: "skip"}}} }

      it "stores a skip row with no connection attached" do
        result

        override = resource.billing_object_connections.sole
        expect(override).to have_attributes(
          category: "tax",
          behavior: "skip",
          payment_provider_customer_id: nil,
          integration_customer_id: nil
        )
      end
    end

    context "with inherit" do
      let(:params) { {connections: {tax: {behavior: "inherit"}}} }

      context "when an override exists" do
        before { create(:billing_object_connection, owner: resource, organization:, category: "tax", behavior: "skip") }

        it "destroys the override so resolution falls back to the customer" do
          expect { result }.to change(BillingObjectConnection, :count).by(-1)
          expect(resource.billing_object_connections.reload).to be_empty
        end
      end

      context "when no override exists" do
        it "is a no-op" do
          expect { result }.not_to change(BillingObjectConnection, :count)
          expect(result).to be_success
        end
      end
    end

    context "when a category is omitted" do
      let(:params) { {connections: {payment: {behavior: "skip"}}} }

      before { create(:billing_object_connection, owner: resource, organization:, category: "tax", behavior: "skip") }

      it "leaves the existing row for that category untouched" do
        expect { result }.to change(BillingObjectConnection, :count).by(1)
        expect(resource.billing_object_connections.reload.pluck(:category)).to match_array(%w[payment tax])
      end
    end

    context "when the same category is written twice" do
      let(:params) { {connections: {payment: {code: "stripe_us"}}} }

      before do
        stripe_connection
        create(:billing_object_connection, owner: resource, organization:, category: "payment", behavior: "skip")
      end

      it "updates the existing row rather than duplicating it" do
        expect { result }.not_to change(BillingObjectConnection, :count)

        expect(resource.billing_object_connections.sole).to have_attributes(
          behavior: "specific",
          payment_provider_customer_id: stripe_connection.id
        )
      end
    end

    context "when the code does not resolve" do
      let(:params) { {connections: {payment: {code: "does_not_exist"}}} }

      it "fails with connection_not_found" do
        expect(result).not_to be_success
        expect(result.error.messages[:connections]).to include("connection_not_found")
      end

      it "does not persist anything" do
        expect { result }.not_to change(BillingObjectConnection, :count)
      end
    end

    context "when the code belongs to another customer" do
      let(:other_customer) { create(:customer, organization:) }
      let(:params) { {connections: {payment: {code: "stripe_other"}}} }

      before { create(:stripe_customer, customer: other_customer, code: "stripe_other") }

      it "fails with connection_not_found" do
        expect(result).not_to be_success
        expect(result.error.messages[:connections]).to include("connection_not_found")
      end
    end

    context "when the code exists but in another category" do
      let(:params) { {connections: {crm: {code: "netsuite_main"}}} }

      before { netsuite_connection }

      it "fails with connection_not_found" do
        expect(result).not_to be_success
        expect(result.error.messages[:connections]).to include("connection_not_found")
      end
    end

    context "when one category resolves and a later one does not" do
      let(:params) do
        {connections: {payment: {code: "stripe_us"}, accounting: {code: "nope"}}}
      end

      before { stripe_connection }

      it "rolls back the rows written before the failure" do
        expect { result }.not_to change(BillingObjectConnection, :count)
        expect(result).not_to be_success
      end
    end

    context "when the resource is a recurring transaction rule" do
      let(:wallet) { create(:wallet, customer:, organization:) }
      let(:resource) { create(:recurring_transaction_rule, wallet:, organization:) }
      let(:params) { {connections: {payment: {code: "stripe_us"}}} }

      before { stripe_connection }

      it "owns the connection by the rule" do
        result

        override = resource.billing_object_connections.sole
        expect(override).to have_attributes(
          owner_id: resource.id,
          owner_type: "RecurringTransactionRule",
          payment_provider_customer_id: stripe_connection.id
        )
      end
    end

    context "with every category at once" do
      let(:params) do
        {
          connections: {
            payment: {code: "stripe_us"},
            tax: {behavior: "skip"},
            accounting: {code: "netsuite_main"},
            crm: {behavior: "skip"}
          }
        }
      end

      before do
        stripe_connection
        netsuite_connection
      end

      it "writes one row per category" do
        expect { result }.to change(BillingObjectConnection, :count).by(4)
        expect(result.billing_object_connections.pluck(:category)).to match_array(%w[payment tax accounting crm])
      end
    end
  end
end
