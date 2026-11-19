# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectionResolvable do
  let(:organization) { create(:organization) }

  describe "#connection_routing", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
    let(:connection_routings) do
      RecurringTransactionRule
        .where(organization:)
        #.includes(:billing_object_connections, customer: %i[payment_provider_customers integration_customers])
        .map(&:connection_routing)
    end

    before do
      3.times do
        customer = create(:customer, organization:)
        wallet = create(:wallet, customer:, organization:)
        rule = create(:recurring_transaction_rule, wallet:, organization:)

        stripe = create(:stripe_customer, customer:, organization:, is_default: true)
        netsuite = create(:netsuite_customer, customer:, organization:, is_default: true)
        create(:hubspot_customer, customer:, organization:, is_default: true)

        gocardless = create(:gocardless_customer, customer:, organization:)
        xero = create(:xero_customer, customer:, organization:)

        create(:billing_object_connection, owner: wallet, organization:, category: :payment,
          behavior: :specific, payment_provider_customer: gocardless)

        create(:billing_object_connection, owner: rule, organization:, category: :accounting,
          behavior: :specific, integration_customer: xero)
      end
    end

    it "does not trigger N+1 queries" do
      expect(connection_routings.size).to eq(3)
    end
  end
end
