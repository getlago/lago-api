# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::InvoiceGroupingService do
  subject(:result) { described_class.call(subscriptions:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer, refind: true) { create(:customer, organization:) }
  let_it_be(:plan) { create(:plan, organization:, amount_currency: "EUR") }

  let(:subscription1) { create(:subscription, customer:, plan:) }
  let(:subscription2) { create(:subscription, customer:, plan:) }
  let(:subscriptions) { [subscription1, subscription2] }

  describe "#call" do
    context "when subscriptions share every grouping criterion" do
      it "returns a single group" do
        expect(result).to be_success
        expect(result.subscription_groups).to eq([[subscription1, subscription2]])
      end
    end

    context "when there is a single subscription" do
      let(:subscriptions) { [subscription1] }

      it "returns a single group" do
        expect(result.subscription_groups).to eq([[subscription1]])
      end
    end

    context "when there is no subscription" do
      let(:subscriptions) { [] }

      it "returns no group" do
        expect(result.subscription_groups).to eq([])
      end
    end

    context "when subscriptions have different payment method types" do
      let(:subscription2) { create(:subscription, customer:, plan:, payment_method_type: "manual") }

      it "returns one group per payment method" do
        expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
      end
    end

    context "when a subscription without payment method resolves to the customer's default one" do
      let(:payment_method) { create(:payment_method, customer:, organization:, is_default: true) }
      let(:subscription1) { create(:subscription, customer:, plan:, payment_method:, payment_method_type: "provider") }
      let(:subscription2) { create(:subscription, customer:, plan:, payment_method: nil, payment_method_type: "provider") }

      it "returns a single group" do
        expect(result.subscription_groups).to eq([[subscription1, subscription2]])
      end
    end

    context "when subscriptions have different explicit payment methods" do
      let(:payment_method1) { create(:payment_method, customer:, organization:, is_default: true) }
      let(:payment_method2) { create(:payment_method, customer:, organization:, is_default: false) }
      let(:subscription1) { create(:subscription, customer:, plan:, payment_method: payment_method1, payment_method_type: "provider") }
      let(:subscription2) { create(:subscription, customer:, plan:, payment_method: payment_method2, payment_method_type: "provider") }

      it "returns one group per payment method" do
        expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
      end
    end

    context "when subscriptions have different currencies" do
      let(:usd_plan) { create(:plan, organization:, amount_currency: "USD") }
      let(:subscription2) { create(:subscription, customer:, plan: usd_plan) }

      it "returns one group per currency" do
        expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
      end
    end

    context "when subscriptions have different billing entities" do
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:subscription2) { create(:subscription, customer:, plan:, billing_entity:) }

      it "returns one group per billing entity" do
        expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
      end
    end

    context "when one subscription inherits the customer's billing entity and the other sets it explicitly" do
      let(:subscription1) { create(:subscription, customer:, plan:, billing_entity: nil) }
      let(:subscription2) { create(:subscription, customer:, plan:, billing_entity: customer.billing_entity) }

      it "returns a single group" do
        expect(result.subscription_groups).to eq([[subscription1, subscription2]])
      end
    end

    context "when a subscription opts out of invoice consolidation" do
      let(:subscription3) { create(:subscription, customer:, plan:) }
      let(:subscription2) { create(:subscription, customer:, plan:, consolidate_invoice: false) }
      let(:subscriptions) { [subscription1, subscription2, subscription3] }

      it "bills the opted-out subscription on its own and consolidates the others" do
        expect(result.subscription_groups).to eq([[subscription2], [subscription1, subscription3]])
      end
    end

    context "when opted-out subscriptions share their external_id" do
      let(:subscription1) { create(:subscription, :terminated, customer:, plan:, external_id: "sub-1", consolidate_invoice: false) }
      let(:subscription2) { create(:subscription, customer:, plan:, external_id: "sub-1", consolidate_invoice: false) }
      let(:subscription3) { create(:subscription, customer:, plan:, external_id: "sub-2", consolidate_invoice: false) }
      let(:subscriptions) { [subscription1, subscription2, subscription3] }

      it "keeps the rows of one subscription together and apart from the others" do
        expect(result.subscription_groups).to eq([[subscription1, subscription2], [subscription3]])
      end

      context "when they also differ on another grouping criterion" do
        let(:billing_entity) { create(:billing_entity, organization:) }
        let(:subscription2) do
          create(:subscription, customer:, plan:, external_id: "sub-1", consolidate_invoice: false, purchase_order_number: "PO-2")
        end
        let(:subscription3) do
          create(:subscription, :terminated, customer:, plan:, external_id: "sub-1", consolidate_invoice: false, billing_entity:)
        end

        it "still splits them on that criterion" do
          expect(result.subscription_groups).to eq([[subscription1], [subscription2], [subscription3]])
        end
      end
    end

    context "when subscriptions have different purchase order numbers" do
      let(:subscription1) { create(:subscription, customer:, plan:, purchase_order_number: "PO-1") }
      let(:subscription2) { create(:subscription, customer:, plan:, purchase_order_number: "PO-2") }

      it "returns one group per purchase order number" do
        expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
      end
    end

    context "when subscriptions have different connections" do
      def create_connection(owner, category, **attributes)
        create(:billing_object_connection, owner:, organization:, category:, behavior: "specific", **attributes)
      end

      context "when the multi_connection feature flag is disabled" do
        before do
          create_connection(subscription1, "accounting", integration_customer: create(:netsuite_customer, customer:))
          create_connection(subscription2, "accounting", integration_customer: create(:xero_customer, customer:))
        end

        it "ignores connections and returns a single group" do
          expect(result.subscription_groups).to eq([[subscription1, subscription2]])
        end
      end

      context "when the multi_connection feature flag is enabled" do
        let_it_be(:organization) { create(:organization, feature_flags: [:multi_connection]) }
        let_it_be(:customer, refind: true) { create(:customer, organization:) }
        let_it_be(:plan) { create(:plan, organization:, amount_currency: "EUR") }

        context "when subscriptions have different payment connections" do
          before do
            create_connection(subscription1, "payment", payment_provider_customer: create(:stripe_customer, customer:))
            create_connection(subscription2, "payment", payment_provider_customer: create(:gocardless_customer, customer:))
          end

          it "returns one group per payment connection" do
            expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
          end
        end

        context "when subscriptions have different tax connections" do
          let(:anrok_customer) { create(:anrok_customer, customer:) }
          let(:avalara_customer) { build(:avalara_customer, customer:).tap { |ic| ic.save!(validate: false) } }

          before do
            create_connection(subscription1, "tax", integration_customer: anrok_customer)
            create_connection(subscription2, "tax", integration_customer: avalara_customer)
          end

          it "returns one group per tax connection" do
            expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
          end
        end

        context "when subscriptions have different accounting connections" do
          before do
            create_connection(subscription1, "accounting", integration_customer: create(:netsuite_customer, customer:))
            create_connection(subscription2, "accounting", integration_customer: create(:xero_customer, customer:))
          end

          it "returns one group per accounting connection" do
            expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
          end
        end

        context "when subscriptions have different crm connections" do
          before do
            create_connection(subscription1, "crm", integration_customer: create(:netsuite_customer, customer:))
            create_connection(subscription2, "crm", integration_customer: create(:xero_customer, customer:))
          end

          it "returns one group per accounting connection" do
            expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
          end
        end

        context "when a subscription skips a connection the other one inherits" do
          before do
            create(:anrok_customer, customer:)
            create(:billing_object_connection, owner: subscription1, organization:, category: "tax", behavior: "skip")
          end

          it "returns one group per subscription" do
            expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
          end
        end

        context "when a subscription pins the connection the other one inherits" do
          before do
            create_connection(subscription1, "crm", integration_customer: create(:hubspot_customer, customer:))
          end

          it "returns a single group" do
            expect(result.subscription_groups).to eq([[subscription1, subscription2]])
          end
        end

        context "when the customer has several connections of the same category" do
          let(:netsuite_customer) { create(:netsuite_customer, customer:, is_default: true) }

          before do
            create(:xero_customer, customer:)
            create_connection(subscription1, "accounting", integration_customer: netsuite_customer)
          end

          it "resolves the inherited connection to the customer default" do
            expect(result.subscription_groups).to eq([[subscription1, subscription2]])
          end
        end

        context "when a subscription pins a connection that is not the customer default" do
          before do
            create(:netsuite_customer, customer:, is_default: true)
            create_connection(subscription1, "accounting", integration_customer: create(:xero_customer, customer:))
          end

          it "returns one group per subscription" do
            expect(result.subscription_groups).to eq([[subscription1], [subscription2]])
          end
        end

        context "when subscriptions have no connection override" do
          before { create(:netsuite_customer, customer:) }

          it "returns a single group" do
            expect(result.subscription_groups).to eq([[subscription1, subscription2]])
          end
        end
      end
    end

    context "when subscriptions differ on several criteria" do
      let(:usd_plan) { create(:plan, organization:, amount_currency: "USD") }
      let(:billing_entity) { create(:billing_entity, organization:) }

      let(:subscription3) { create(:subscription, customer:, plan: usd_plan) }
      let(:subscription4) { create(:subscription, customer:, plan:, billing_entity:) }
      let(:subscription5) { create(:subscription, customer:, plan:, billing_entity:, purchase_order_number: "PO-1") }
      let(:subscriptions) { [subscription1, subscription2, subscription3, subscription4, subscription5] }

      it "returns one group per combination of criteria" do
        expect(result.subscription_groups).to eq(
          [[subscription1, subscription2], [subscription4], [subscription5], [subscription3]]
        )
      end
    end
  end
end
